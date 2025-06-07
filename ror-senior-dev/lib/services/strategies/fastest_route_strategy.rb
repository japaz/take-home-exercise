# frozen_string_literal: true

require_relative 'base_strategy'

module RouteFinder
  module Strategies
    # Strategy for finding the FASTEST route.
    class FastestRouteStrategy < BaseStrategy
      def find_direct_route(service, origin, destination)
        service.find_fastest_direct(origin, destination)
      end

      def get_solution_metric(solution)
        return Float::INFINITY if solution.empty?

        start_date = solution.first['departure_date_obj']
        end_date = solution.last['arrival_date_obj']

        (end_date - start_date).to_i
      end

      def create_next_node(current_node, sailing)
        start_date = current_node.start_date || sailing['departure_date_obj']
        journey_time = (sailing['arrival_date_obj'] - start_date).to_i

        RouteFinder::RouteFinderService::Node.new(
          sailing['destination_port'],
          journey_time,
          sailing['arrival_date_obj'],
          start_date,
          current_node.path_legs + 1,
          current_node.deferred
        )
      end
    end
  end
end
