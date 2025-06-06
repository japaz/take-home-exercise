# frozen_string_literal: true

require 'pqueue'
require 'date'
require_relative '../errors/application_error'
require_relative '../validators/port_code_validator'

module RouteFinder
  # Service to find the cheapest or fastest sailing routes.
  class RouteFinderService
    # Initialize the service with sailing, rate, and exchange rate data.
    def initialize(sailings, rates, exchange_rates)
      validate_init_parameters(sailings, rates, exchange_rates)

      @rates_by_code = rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }
      @cost_cache = {}
      @exchange_rates = process_exchange_rates(exchange_rates)
      @port_connections = process_sailings_and_connections(sailings)
    end

    # Finds the cheapest direct sailing route.
    def find_cheapest_direct(origin, destination)
      validate_port_codes(origin, destination)

      find_best_direct(origin, destination) do |sailing|
        calculate_cost_in_eur_cents(sailing)
      end
    end

    # Finds the fastest direct sailing route.
    def find_fastest_direct(origin, destination)
      validate_port_codes(origin, destination)

      find_best_direct(origin, destination) do |sailing|
        (sailing['arrival_date_obj'] - sailing['departure_date_obj']).to_i
      end
    end

    # Finds the cheapest route (direct or indirect).
    def find_cheapest_route(origin, destination)
      validate_port_codes(origin, destination)

      strategy = CheapestRouteStrategy.new(method(:calculate_cost_in_eur_cents))
      find_route(origin, destination, strategy)
    end

    # Finds the fastest route (direct or indirect).
    def find_fastest_route(origin, destination)
      validate_port_codes(origin, destination)

      strategy = FastestRouteStrategy.new
      find_route(origin, destination, strategy)
    end

    private

    # Validates that port codes follow the expected format and exist in our data
    def validate_port_codes(origin, destination)
      Validators::PortCodeValidator.validate!(origin, 'origin')
      Validators::PortCodeValidator.validate!(destination, 'destination')

      # Check if origin port exists in our data
      return if @port_connections.key?(origin)

      raise Errors::InvalidRouteError, "No sailings found from origin port: #{origin}"
    end

    # Validates initialization parameters
    def validate_init_parameters(sailings, rates, exchange_rates)
      raise Errors::ValidationError, 'Sailings data cannot be nil' if sailings.nil?
      raise Errors::ValidationError, 'Rates data cannot be nil' if rates.nil?
      raise Errors::ValidationError, 'Exchange rates data cannot be nil' if exchange_rates.nil?

      raise Errors::ValidationError, 'Sailings must be an array' unless sailings.is_a?(Array)

      raise Errors::ValidationError, 'Rates must be an array' unless rates.is_a?(Array)

      raise Errors::ValidationError, 'Exchange rates must be a hash/object' unless exchange_rates.is_a?(Hash)
    end

    # Generic route-finding algorithm using a strategy for cost/time optimization.
    def find_route(origin, destination, strategy)
      # First, find the best direct route to set a baseline for optimization.
      direct_route = strategy.find_direct_route(self, origin, destination)

      best_solution = direct_route
      best_solution_metric = strategy.get_solution_metric(best_solution)

      # Initialize priority queue for Dijkstra's algorithm.
      pq = PQueue.new(&strategy.method(:compare_nodes))
      pq.push(strategy.create_initial_node(origin))

      predecessors = {}
      visited_costs = Hash.new { |h, k| h[k] = Float::INFINITY }

      # Main algorithm loop
      until pq.empty?
        current_node = pq.pop

        # Pruning: If the current path is already worse than our best found solution, skip.
        next if strategy.prune?(current_node, best_solution_metric)

        # Check if we've reached the destination.
        if current_node.port == destination
          # If we found a better solution, update the best known.
          if strategy.is_better_solution?(current_node, best_solution_metric)
            best_solution_metric = strategy.get_node_metric(current_node)
            best_solution = reconstruct_path(predecessors, current_node)
          end
          next
        end

        # Explore next possible sailings.
        next_sailings = find_next_valid_sailings(current_node)
        next_sailings.each do |sailing|
          next_node = strategy.create_next_node(current_node, sailing)
          next unless next_node

          # If we've found a more expensive path to the same port, skip.
          next if next_node.cost >= visited_costs[next_node.port]

          visited_costs[next_node.port] = next_node.cost
          predecessors[next_node] = { previous_node: current_node, sailing: sailing }
          pq.push(next_node)
        end
      end

      strategy.finalize_result(best_solution)
    rescue StandardError => e
      raise Errors::ApplicationError, "Error finding route: #{e.message}"
    end

    # Abstract base class for routing strategies.
    class BaseStrategy
      # A simple container for the state of our search algorithm.
      Node = Struct.new(:port, :cost, :secondary_metric, :arrival_date, :start_date, :path_legs)

      # Default comparison for the priority queue.
      def compare_nodes(a, b)
        a.cost < b.cost
      end

      # Checks if a potential path should be abandoned early.
      def prune?(node, best_solution_metric)
        node.cost >= best_solution_metric[:cost]
      end

      # Checks if the newly found complete route is better than the best one so far.
      def is_better_solution?(node, best_solution_metric)
        node.cost < best_solution_metric[:cost]
      end

      # Extracts the relevant metrics from a node.
      def get_node_metric(node)
        { cost: node.cost, secondary: node.secondary_metric }
      end

      # Extracts metrics from a full solution path.
      def get_solution_metric(solution)
        return { cost: Float::INFINITY, secondary: nil } if solution.empty?

        cost = solution.sum { |leg| leg[:cost_in_cents] }
        { cost: cost, secondary: nil }
      end

      # Processes the final path before returning it.
      def finalize_result(path)
        path
      end
    end

    # Strategy for finding the CHEAPEST route.
    class CheapestRouteStrategy < BaseStrategy
      def initialize(cost_calculator)
        @cost_calculator = cost_calculator
        super()
      end

      def find_direct_route(service, origin, destination)
        service.find_cheapest_direct(origin, destination)
      end

      def create_initial_node(origin)
        Node.new(origin, 0, nil, nil, nil, 0)
      end

      def create_next_node(current_node, sailing)
        sailing_cost = @cost_calculator.call(sailing)
        return nil unless sailing_cost

        Node.new(
          sailing['destination_port'],
          current_node.cost + sailing_cost,
          nil,
          sailing['arrival_date_obj'],
          current_node.start_date || sailing['departure_date_obj'],
          current_node.path_legs + 1
        )
      end

      def finalize_result(path)
        # Add the calculated rate in EUR cents to each leg of the journey
        path.map do |sailing|
          rate_eur_cents = @cost_calculator.call(sailing)
          sailing.merge('rate_eur_cents' => rate_eur_cents)
        end
      end
    end

    # Strategy for finding the FASTEST route.
    class FastestRouteStrategy < BaseStrategy
      def find_direct_route(service, origin, destination)
        service.find_fastest_direct(origin, destination)
      end

      def compare_nodes(a, b)
        return a.cost < b.cost if a.cost != b.cost

        a.secondary_metric < b.secondary_metric # Earliest arrival is better
      end

      def prune?(node, best_solution_metric)
        return true if node.cost > best_solution_metric[:cost]

        node.cost == best_solution_metric[:cost] && node.secondary_metric >= best_solution_metric[:secondary]
      end

      def is_better_solution?(node, best_solution_metric)
        return true if node.cost < best_solution_metric[:cost]

        node.cost == best_solution_metric[:cost] && node.secondary_metric < best_solution_metric[:secondary]
      end

      def get_solution_metric(solution)
        return { cost: Float::INFINITY, secondary: nil } if solution.empty?

        start_date = solution.first['departure_date_obj']
        end_date = solution.last['arrival_date_obj']

        { cost: (end_date - start_date).to_i, secondary: end_date }
      end

      def create_initial_node(origin)
        Node.new(origin, 0, nil, nil, nil, 0)
      end

      def create_next_node(current_node, sailing)
        start_date = current_node.start_date || sailing['departure_date_obj']
        journey_time = (sailing['arrival_date_obj'] - start_date).to_i

        Node.new(
          sailing['destination_port'],
          journey_time,
          sailing['arrival_date_obj'], # Secondary metric: arrival date
          sailing['arrival_date_obj'],
          start_date,
          current_node.path_legs + 1
        )
      end
    end

    # Generic method to find the single best direct sailing based on a metric.
    def find_best_direct(origin, destination)
      best_sailing = nil
      min_metric = Float::INFINITY

      return [] unless @port_connections[origin]

      @port_connections[origin].each do |sailing|
        next unless sailing['destination_port'] == destination

        # The block here calculates the metric (cost or time)
        metric = yield(sailing)
        next if metric.nil? || metric >= min_metric

        min_metric = metric
        best_sailing = sailing
      end

      best_sailing ? [best_sailing.merge(cost_in_cents: min_metric)] : []
    end

    # Pre-processes sailings: filters invalid ones, merges rate data, and groups by origin.
    def process_sailings_and_connections(sailings)
      connections = Hash.new { |h, k| h[k] = [] }

      sailings.each do |sailing|
        rate_info = @rates_by_code[sailing['sailing_code']]
        next unless rate_info && has_valid_rate?(sailing, rate_info)

        begin
          sailing.merge!(
            'rate' => rate_info['rate'],
            'rate_currency' => rate_info['rate_currency'],
            'departure_date_obj' => Date.parse(sailing['departure_date']),
            'arrival_date_obj' => Date.parse(sailing['arrival_date'])
          )
          connections[sailing['origin_port']] << sailing
        rescue Date::Error
          next # Skip sailings with invalid dates.
        end
      end

      # Sort sailings by departure date for efficient searching later.
      connections.each_value { |sailing_list| sailing_list.sort_by! { |s| s['departure_date_obj'] } }
      connections
    end

    # Checks if a sailing has a valid, convertible rate.
    def has_valid_rate?(sailing, rate_info)
      currency = rate_info['rate_currency'].downcase
      return true if currency == 'eur'

      @exchange_rates.dig(sailing['departure_date'], currency)&.positive?
    end

    # Scales exchange rates to integers for precise calculations.
    def process_exchange_rates(exchange_rates)
      scale_factor = 10_000
      exchange_rates.each_with_object({}) do |(date, rates), result|
        result[date] = rates.transform_values do |rate|
          (rate.to_f * scale_factor).round if rate
        end
      end
    end

    # Finds all valid sailings from a port after a node's arrival.
    def find_next_valid_sailings(current_node)
      sailings = @port_connections[current_node.port] || []
      return [] if sailings.empty? || current_node.path_legs > 10 # Safety break for long routes

      # If it's not the start, find sailings departing after the last arrival.
      if current_node.arrival_date
        # bsearch_index is fast (O(log n)) because we pre-sorted the sailings.
        start_index = sailings.bsearch_index { |s| s['departure_date_obj'] > current_node.arrival_date }
        return [] if start_index.nil?

        sailings = sailings[start_index..-1]
      end
      sailings
    end

    # Reconstructs the final path from the predecessors map.
    def reconstruct_path(predecessors, end_node)
      path = []
      current = end_node
      while current && predecessors[current]
        info = predecessors[current]
        path.unshift(info[:sailing])
        current = info[:previous_node]
      end
      path
    end

    # Calculates the cost of a single sailing in EUR cents, with caching.
    def calculate_cost_in_eur_cents(sailing)
      return @cost_cache[sailing['sailing_code']] if @cost_cache.key?(sailing['sailing_code'])

      rate_in_cents = (sailing['rate'].to_f * 100).round
      currency = sailing['rate_currency'].downcase

      cost = if currency == 'eur'
               rate_in_cents
             else
               exchange_rate = @exchange_rates.dig(sailing['departure_date'], currency)
               return nil unless exchange_rate&.positive?

               (rate_in_cents * 10_000) / exchange_rate
             end

      @cost_cache[sailing['sailing_code']] = cost
    rescue StandardError => e
      raise Errors::CalculationError, "Error calculating cost for sailing #{sailing['sailing_code']}: #{e.message}"
    end
  end
end
