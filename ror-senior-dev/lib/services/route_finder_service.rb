# frozen_string_literal: true

require 'pqueue'
require 'date'

module RouteFinder
  class RouteFinderService
    def initialize(sailings, rates, exchange_rates)
      @sailings = sailings
      @rates = rates
      @exchange_rates = exchange_rates
      @rates_by_code = @rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }

      # Process and filter sailings once during initialization
      @processed_sailings = process_sailings(@sailings)

      # Create an adjacency list for faster lookup
      @port_connections = build_port_connections
    end

    def find_cheapest_direct(origin, destination)
      min_rate_eur_cents = nil
      cheapest = []

      @sailings.each do |sailing|
        next unless sailing['origin_port'] == origin &&
                    sailing['destination_port'] == destination

        rate_info = @rates_by_code[sailing['sailing_code']]
        next unless rate_info

        currency = rate_info['rate_currency'].downcase
        rate_in_currency = rate_info['rate'].to_f

        if currency == 'eur'
          # EUR is the base currency, no conversion needed
          rate_eur = rate_in_currency
        else
          currency_rate = @exchange_rates.dig(sailing['departure_date'], currency)
          next unless currency_rate&.positive?

          rate_eur = rate_in_currency / currency_rate.to_f
        end

        rate_eur_cents = (rate_eur * 100).round

        next unless min_rate_eur_cents.nil? || rate_eur_cents < min_rate_eur_cents

        min_rate_eur_cents = rate_eur_cents
        cheapest = [sailing.merge(
          'rate' => rate_info['rate'],
          'rate_currency' => rate_info['rate_currency'],
          'rate_eur_cents' => rate_eur_cents
        )]
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

      # Add rate information to the final result
      best_solution.map do |sailing|
        rate_info = @rates_by_code[sailing['sailing_code']]
        rate_eur_cents = calculate_cost_in_eur_cents(sailing)
        sailing.merge(
          'rate' => rate_info['rate'],
          'rate_currency' => rate_info['rate_currency'],
          'rate_eur_cents' => rate_eur_cents
        )
      end
    end

    private

    # Process and filter sailings during initialization
    def process_sailings(sailings)
      sailings.select do |sailing|
        rate_info = @rates_by_code[sailing['sailing_code']]
        next false unless rate_info

        currency = rate_info['rate_currency'].downcase

        # EUR is the base currency, only need to check if departure date exists
        if currency == 'eur'
          @exchange_rates.key?(sailing['departure_date'])
        else
          # For other currencies, need exchange rate for the departure date
          next false unless @exchange_rates.key?(sailing['departure_date'])

          currency_rate = @exchange_rates[sailing['departure_date']][currency]
          currency_rate && currency_rate.to_f > 0
        end
      end
    end

    # Build adjacency list for faster lookup of connections
    def build_port_connections
      connections = Hash.new { |h, k| h[k] = [] }
      @processed_sailings.each do |sailing|
        connections[sailing['origin_port']] << sailing
      end
      connections
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
            next false if departure < arrival
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
      rate_info = @rates_by_code[sailing['sailing_code']]
      return nil unless rate_info

      currency = rate_info['rate_currency'].downcase
      rate_in_currency = rate_info['rate'].to_f

      if currency == 'eur'
        # EUR is the base currency, no conversion needed
        rate_eur = rate_in_currency
      else
        currency_rate = @exchange_rates[sailing['departure_date']][currency]
        return nil unless currency_rate && currency_rate.to_f > 0

        rate_eur = rate_in_currency / currency_rate.to_f
      end

      (rate_eur * 100).round
    end
  end
end
