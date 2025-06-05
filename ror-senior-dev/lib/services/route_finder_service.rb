# frozen_string_literal: true

# Validate all the values in the json files and discard all wrong values

require 'pqueue'
require 'date'

module RouteFinder
  class RouteFinderService
    # Constant to represent "infinity" for integer-based cost calculations
    MAX_COST = 2_147_483_647 # Max 32-bit signed integer

    # Initialize the service with data
    def initialize(sailings, rates, exchange_rates)
      @sailings = sailings
      @rates = rates
      @rate_scale = 10_000 # Scale factor for exchange rates
      @rates_by_code = @rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }

      # Process exchange rates first so they're available for sailing processing
      @exchange_rates = process_exchange_rates(exchange_rates)

      # Then process sailings using the processed exchange rates
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
      # Use a very large integer instead of Float::INFINITY to stay in the integer domain
      best_cost = MAX_COST

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

        # Convert rate to integer cents, but keep original rate for backward compatibility
        rate_cents = (rate_info['rate'].to_f * 100).round

        # Pre-parse dates into Date objects to avoid repeated parsing
        begin
          departure_date = Date.parse(sailing['departure_date'])
          arrival_date = Date.parse(sailing['arrival_date'])
        rescue Date::Error
          # Skip sailings with invalid dates
          next
        end

        merged = sailing.merge(
          'rate' => rate_info['rate'], # Keep original rate for backward compatibility
          'rate_cents' => rate_cents,
          'rate_currency' => rate_info['rate_currency'],
          'departure_date_obj' => departure_date,
          'arrival_date_obj' => arrival_date
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
          # Use the pre-parsed date objects instead of parsing again
          departure_date = sailing['departure_date_obj']

          # If we're given a string for prev_arrival_date, parse it once
          arrival_date = prev_arrival_date.is_a?(Date) ? prev_arrival_date : Date.parse(prev_arrival_date)

          # Skip if departure is before or equal to arrival
          next false if departure_date <= arrival_date
        end

        # Don't go to ports we've already visited
        !visited_ports.include?(sailing['destination_port'])
      end
    end

    # Calculate the cost of a sailing in EUR cents
    def calculate_cost_in_eur_cents(sailing)
      # Rate information is already merged in the sailing object
      currency = sailing['rate_currency'].downcase

      # Use rate_cents that we pre-calculated during initialization
      rate_in_cents = sailing['rate_cents']
      return nil unless rate_in_cents

      return rate_in_cents if currency == 'eur'

      # EUR is the base currency, no conversion needed

      scaled_exchange_rate = @exchange_rates.dig(sailing['departure_date'], currency)
      return nil unless scaled_exchange_rate&.positive?

      # Convert to EUR cents using integer arithmetic
      # The formula is: (rate_in_cents * rate_scale) / scaled_exchange_rate
      # This keeps everything in integer domain until the final division
      (rate_in_cents * @rate_scale) / scaled_exchange_rate
    end

    # Process exchange rates to convert them to integers
    def process_exchange_rates(exchange_rates)
      # Scale factor for exchange rates
      scale_factor = @rate_scale

      # Convert exchange rates to integers (cents)
      exchange_rates.each_with_object({}) do |(date, rates), result|
        result[date] = rates.transform_values do |rate|
          rate ? (rate.to_f * scale_factor).round : nil
        end
      end
    end
  end
end
