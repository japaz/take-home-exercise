# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/services/route_finder_service'

# This file contains shared examples and common test setup for the RouteFinderService specs
# The actual tests have been moved to specific spec files for each functionality
# - route_finder_service_cheapest_direct_spec.rb: Tests for #find_cheapest_direct method
# - route_finder_service_cheapest_route_spec.rb: Tests for #find_cheapest_route method
# - route_finder_service_fastest_spec.rb: Tests for #find_fastest_route method

RSpec.describe RouteFinder::RouteFinderService do
  # Each individual test file now has its own fixture definitions
  # This file is kept for reference and to maintain the file structure
end
