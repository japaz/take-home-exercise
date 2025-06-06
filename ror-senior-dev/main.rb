#!/usr/bin/env ruby

# frozen_string_literal: true

require 'json'
require_relative 'lib/data_loader'
require_relative 'lib/services/route_finder_service'

# Main application entry point
# Reads input from stdin and outputs to stdout
def main
  # Read input
  origin_port = gets.chomp
  destination_port = gets.chomp
  criteria = gets.chomp

  # Load data from response.json
  data_loader = RouteFinder::DataLoader.new('response.json')
  service = data_loader.create_service

  # Find route based on criteria
  result = case criteria
           when 'cheapest-direct'
             service.find_cheapest_direct(origin_port, destination_port)
           when 'cheapest'
             service.find_cheapest_route(origin_port, destination_port)
           when 'fastest'
             service.find_fastest_route(origin_port, destination_port)
           else
             []
           end

  # Format and output result
  formatted_result = result.map do |sailing|
    {
      'origin_port' => sailing['origin_port'],
      'destination_port' => sailing['destination_port'],
      'departure_date' => sailing['departure_date'],
      'arrival_date' => sailing['arrival_date'],
      'sailing_code' => sailing['sailing_code'],
      'rate' => sailing['rate'],
      'rate_currency' => sailing['rate_currency']
    }
  end

  puts JSON.pretty_generate(formatted_result)
end

# Run the application if this file is executed directly
main if __FILE__ == $PROGRAM_NAME
