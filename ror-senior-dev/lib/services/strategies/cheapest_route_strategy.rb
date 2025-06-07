# frozen_string_literal: true

require_relative 'base_strategy'

module RouteFinder
  module Strategies
    # Strategy for finding the CHEAPEST route.
    class CheapestRouteStrategy < BaseStrategy
      def initialize(cost_calculator)
        @cost_calculator = cost_calculator
        super()
      end

      def find_direct_route(service, origin, destination)
        service.find_cheapest_direct(origin, destination)
      end

      # Extracts metrics from a full solution path for the cheapest route strategy
      def get_solution_metric(solution)
        return Float::INFINITY if solution.empty?

        solution.sum { |leg| leg[:cost_in_cents] }
      end

      def create_next_node(current_node, sailing)
        sailing_cost = @cost_calculator.call(sailing)
        return nil unless sailing_cost

        RouteFinder::RouteFinderService::Node.new(
          sailing['destination_port'],
          current_node.cost + sailing_cost,
          sailing['arrival_date_obj'],
          current_node.start_date || sailing['departure_date_obj'],
          current_node.path_legs + 1,
          current_node.deferred
        )
      end
    end
  end
end
