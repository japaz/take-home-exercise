# frozen_string_literal: true

# Validate all the values in the json files and discard all wrong values

require 'pqueue'
require 'date'

module RouteFinder
  class RouteFinderService
    def initialize(sailings, rates, exchange_rates)
      @sailings = sailings
      @rates = rates
      @exchange_rates = exchange_rates
      @rates_by_code = @rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }

      @processed_sailings, @port_connections = process_sailings_and_connections(@sailings)
    end

    def find_cheapest_direct(origin, destination)
      min_rate_eur_cents = nil
      cheapest = []

      # Use port_connections to only check sailings from the origin port
      origin_sailings = @port_connections[origin] || []

      origin_sailings.each do |sailing|
        next unless sailing['destination_port'] == destination

        rate_eur_cents = calculate_cost_in_eur_cents(sailing)
        next unless rate_eur_cents # Skip if rate calculation failed

        next unless min_rate_eur_cents.nil? || rate_eur_cents < min_rate_eur_cents

        min_rate_eur_cents = rate_eur_cents
        cheapest = [sailing.merge('rate_eur_cents' => rate_eur_cents)]
      end

      cheapest.empty? ? [] : cheapest
    end

    # Finds the cheapest route from origin to destination, which can be direct or indirect
    def find_cheapest_route(origin, destination)
      # Check direct routes first
      direct_route = find_cheapest_direct(origin, destination)

      # Initialize priority queue with starting point
      queue = PQueue.new { |a, b| a[:cost] < b[:cost] }
      queue.push({
                   port: origin,
                   cost: 0,
                   arrival_date: nil,
                   path: [],
                   visited: Set.new([origin])
                 })

      # Track best solution found so far
      best_solution = nil
      best_cost = Float::INFINITY

      # If we have a direct route, use its cost as initial best cost
      if direct_route.any?
        best_cost = direct_route.first['rate_eur_cents']
        best_solution = direct_route
      end

      # Dijkstra's algorithm with early termination
      until queue.empty?
        current = queue.pop

        # Skip if we've already found a better solution
        next if current[:cost] >= best_cost

        current_port = current[:port]

        # Check if we've reached the destination
        if current_port == destination && current[:path].any?
          if current[:cost] < best_cost
            best_cost = current[:cost]
            best_solution = current[:path]
          end
          next
        end

        # Get all valid sailings from current port
        next_sailings = next_valid_sailings(current_port, current[:arrival_date], current[:visited])

        # Explore each sailing
        next_sailings.each do |sailing|
          next_port = sailing['destination_port']

          # Skip if we've already visited this port (no cycles allowed)
          next if current[:visited].include?(next_port)

          # Calculate cost for this sailing
          sailing_cost = calculate_cost_in_eur_cents(sailing)
          next if sailing_cost.nil? # Skip if we can't determine cost

          # Calculate new total cost
          new_cost = current[:cost] + sailing_cost

          # Skip if cost exceeds the best solution
          next if new_cost >= best_cost

          # Create new path with this sailing
          new_path = current[:path] + [sailing]

          # Add to queue with updated state
          new_visited = current[:visited].dup
          new_visited.add(next_port)
          queue.push({
                       port: next_port,
                       cost: new_cost,
                       arrival_date: sailing['arrival_date'],
                       path: new_path,
                       visited: new_visited
                     })
        end
      end

      # If no solution was found, return empty array
      return [] unless best_solution

      # If best solution is already a processed direct route, return it directly
      return best_solution if best_solution.is_a?(Array) && best_solution.first.key?('rate')

      # Add rate_eur_cents information to the final result
      best_solution.map do |sailing|
        rate_eur_cents = calculate_cost_in_eur_cents(sailing)
        sailing.merge('rate_eur_cents' => rate_eur_cents)
      end
    end

    private

    # Process and filter sailings during initialization
    # Merge sailing and rate information, discarding sailings without valid rates
    def process_sailings_and_connections(sailings)
      connections = Hash.new { |h, k| h[k] = [] }
      processed = sailings.filter_map do |sailing|
        rate_info = @rates_by_code[sailing['sailing_code']]
        next unless rate_info

        currency = rate_info['rate_currency'].downcase
        next unless currency == 'eur' ||
                    @exchange_rates.dig(sailing['departure_date'], currency)&.positive?

        merged = sailing.merge(
          'rate' => rate_info['rate'],
          'rate_currency' => rate_info['rate_currency']
        )
        connections[merged['origin_port']] << merged
        merged
      end
      [processed, connections]
    end

    # Find all valid next sailings from a port after a specific date
    def next_valid_sailings(port, prev_arrival_date, visited_ports)
      sailings = @port_connections[port] || []
      sailings.select do |sailing|
        # Check if departure date is on or after previous arrival
        if prev_arrival_date
          begin
            departure = Date.parse(sailing['departure_date'])
            arrival = Date.parse(prev_arrival_date)
            next false if departure <= arrival
          rescue Date::Error
            next false # Skip if dates can't be parsed
          end
        end

        # Don't go to ports we've already visited
        !visited_ports.include?(sailing['destination_port'])
      end
    end

    # Calculate the cost of a sailing in EUR cents
    def calculate_cost_in_eur_cents(sailing)
      # Rate information is already merged in the sailing object
      currency = sailing['rate_currency'].downcase
      rate_in_currency = sailing['rate'].to_f

      if currency == 'eur'
        # EUR is the base currency, no conversion needed
        rate_eur = rate_in_currency
      else
        currency_rate = @exchange_rates[sailing['departure_date']][currency]
        return nil unless currency_rate&.positive?

        rate_eur = rate_in_currency / currency_rate.to_f
      end

      (rate_eur * 100).round
    end
  end
end
