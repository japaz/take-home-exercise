# frozen_string_literal: true

require 'pqueue'
require 'date'
require_relative '../errors/application_error'
require_relative '../validators/port_code_validator'
require_relative 'strategies/base_strategy'
require_relative 'strategies/cheapest_route_strategy'
require_relative 'strategies/fastest_route_strategy'

module RouteFinder
  # Service to find the cheapest or fastest sailing routes.
  class RouteFinderService
    EXCHANGE_RATE_SCALE_FACTOR = 10_000
    DEFAULT_MAX_PATH_LEGS = 10

    # A simple container for the state of the search algorithm.
    Node = Struct.new(:port, :cost, :arrival_date, :start_date, :path_legs, :deferred)

    # Initialize the service with sailing, rate, and exchange rate data.
    def initialize(sailings, rates, exchange_rates, options = {})
      validate_init_parameters(sailings, rates, exchange_rates)

      @rates_by_code = rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }
      @cost_cache = {}
      @exchange_rates = process_exchange_rates(exchange_rates)
      @port_connections = process_sailings_and_connections(sailings)
      @max_path_legs = options[:max_path_legs] || DEFAULT_MAX_PATH_LEGS
    end

    # Finds the cheapest direct sailing route.
    def find_cheapest_direct(origin, destination)
      validate_port_codes(origin, destination)

      find_best_direct(origin, destination, :cost_in_cents) do |sailing|
        calculate_cost_in_eur_cents(sailing)
      end
    end

    # Finds the fastest direct sailing route.
    def find_fastest_direct(origin, destination)
      validate_port_codes(origin, destination)

      find_best_direct(origin, destination, :duration_in_days) do |sailing|
        # This is the basic cost calculation for fastest route, but we can also use
        # a more complex metric if needed. Like taking into account the arrival date of
        # the different direct sailings
        (sailing['arrival_date_obj'] - sailing['departure_date_obj']).to_i
      end
    end

    # Finds the cheapest route (direct or indirect).
    def find_cheapest_route(origin, destination)
      validate_port_codes(origin, destination)

      strategy = Strategies::CheapestRouteStrategy.new(method(:calculate_cost_in_eur_cents))
      find_route(origin, destination, strategy)
    end

    # Finds the fastest route (direct or indirect).
    def find_fastest_route(origin, destination)
      validate_port_codes(origin, destination)

      strategy = Strategies::FastestRouteStrategy.new
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
      pq = PQueue.new(&method(:compare_nodes))
      pq.push(Node.new(origin, 0, nil, nil, 0, false))

      # Use a hash for tracking visited costs: port -> cost
      visited_costs = Hash.new { |h, k| h[k] = Float::INFINITY }
      predecessors = {}

      # Main algorithm loop
      until pq.empty?
        current_node = pq.pop

        # Pruning: If the current path is already worse than our best found solution, skip.
        next if current_node.cost >= best_solution_metric

        # Check if we've reached the destination.
        if current_node.port == destination
          # If we found a better solution, update the best known.
          if is_better_solution?(current_node, best_solution_metric)
            best_solution_metric = current_node.cost
            best_solution = reconstruct_path(predecessors, current_node)
          end
          next
        end

        # Determine which path length tier this node belongs to
        tier = current_node.path_legs >= @max_path_legs ? :long : :short

        # If this is a long route being processed for the first time, mark it as deferred
        # and push it back to queue with lower priority (unless it's already marked as deferred)
        if tier == :long && !current_node.deferred
          deferred_node = current_node.dup
          deferred_node.deferred = true
          pq.push(deferred_node)
          predecessors[deferred_node] = predecessors[current_node]
          next
        end

        # Explore next possible sailings
        next_sailings = find_next_valid_sailings(current_node)
        next_sailings.each do |sailing|
          next_node = strategy.create_next_node(current_node, sailing)
          next unless next_node

          # Skip if we've found a more optimal path to this port
          next if next_node.cost >= visited_costs[next_node.port]

          # Update visited costs tracker and predecessors
          visited_costs[next_node.port] = next_node.cost
          predecessors[next_node] = { previous_node: current_node, sailing: sailing }

          # Add node to queue
          pq.push(next_node)
        end
      end

      best_solution
    rescue StandardError => e
      raise Errors::ApplicationError, "Error finding route: #{e.message}"
    end

    # Generic method to find the single best direct sailing based on a metric.
    def find_best_direct(origin, destination, metric_name = :cost_in_cents)
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

      best_sailing ? [best_sailing.merge(metric_name => min_metric)] : []
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
      exchange_rates.each_with_object({}) do |(date, rates), result|
        result[date] = rates.transform_values do |rate|
          (rate.to_f * EXCHANGE_RATE_SCALE_FACTOR).round if rate
        end
      end
    end

    # Finds all valid sailings from a port after a node's arrival.
    def find_next_valid_sailings(current_node)
      sailings = @port_connections[current_node.port] || []
      return [] if sailings.empty?

      # If it's not the start, find sailings departing after the last arrival.
      if current_node.arrival_date
        # bsearch_index is fast (O(log n)) because we pre-sorted the sailings.
        start_index = sailings.bsearch_index { |s| s['departure_date_obj'] > current_node.arrival_date }
        return [] if start_index.nil?

        sailings = sailings[start_index..]
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

      # Convert rate to cents (10 EUR -> 1000 cents)
      rate_in_cents = (sailing['rate'].to_f * 100).round
      currency = sailing['rate_currency'].downcase

      cost = if currency == 'eur'
               # For EUR, just use the cents directly
               rate_in_cents
             else
               exchange_rate = @exchange_rates.dig(sailing['departure_date'], currency)
               return nil unless exchange_rate&.positive?

               # For other currencies, convert using exchange rate
               ((rate_in_cents * EXCHANGE_RATE_SCALE_FACTOR) / exchange_rate)
             end

      @cost_cache[sailing['sailing_code']] = cost
    rescue StandardError => e
      raise Errors::CalculationError, "Error calculating cost for sailing #{sailing['sailing_code']}: #{e.message}"
    end

    def compare_nodes(a, b)
      if a.deferred != b.deferred
        # Non-deferred nodes have higher priority
        return a.deferred == false && b.deferred == true
      end

      # For nodes with the same deferred status, compare by cost
      a.cost < b.cost
    end

    # Check if the new solution is better than the current best
    def is_better_solution?(node, best_solution_metric)
      node.cost < best_solution_metric
    end
  end
end
