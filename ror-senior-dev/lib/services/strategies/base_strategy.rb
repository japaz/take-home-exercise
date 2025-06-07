# frozen_string_literal: true

module RouteFinder
  module Strategies
    # Abstract base class for routing strategies.
    class BaseStrategy
      # Finds a direct route between origin and destination.
      # This method must be implemented by subclasses.
      def find_direct_route(service, origin, destination)
        raise NotImplementedError, "#{self.class} must implement #find_direct_route"
      end

      # Extracts metrics from a full solution path.
      # This method must be implemented by subclasses.
      def get_solution_metric(solution)
        raise NotImplementedError, "#{self.class} must implement #get_solution_metric"
      end

      # Creates the next node in the pathfinding process
      # This method must be implemented by subclasses.
      def create_next_node(current_node, sailing)
        raise NotImplementedError, "#{self.class} must implement #create_next_node"
      end
    end
  end
end
