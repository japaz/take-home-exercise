#!/usr/bin/env ruby

# frozen_string_literal: true

require 'json'
require_relative 'lib/data_loader'
require_relative 'lib/services/route_finder_service'
require_relative 'lib/errors/application_error'
require_relative 'lib/validators/port_code_validator'

# Main application entry point
# Reads input from stdin and outputs to stdout
def main
  # Read and validate input
  origin_port = read_and_validate_port_code('origin')
  destination_port = read_and_validate_port_code('destination')
  criteria = read_and_validate_criteria

  if origin_port == destination_port
    warn 'Error: Origin and destination ports cannot be the same.'
    exit(1)
  end

  # Load data from response.json
  data_loader = RouteFinder::DataLoader.new('response.json')

  begin
    service = data_loader.create_service
  rescue RouteFinder::Errors::FileNotFoundError => e
    warn "Error loading data: #{e.message}"
    exit(1)
  rescue RouteFinder::Errors::InvalidDataError => e
    warn "Invalid data format: #{e.message}"
    exit(1)
  rescue JSON::ParserError => e
    warn "JSON parsing error: #{e.message}"
    exit(1)
  end

  # Find route based on criteria
  result = case criteria
           when 'cheapest-direct'
             service.find_cheapest_direct(origin_port, destination_port)
           when 'cheapest'
             service.find_cheapest_route(origin_port, destination_port)
           when 'fastest'
             service.find_fastest_route(origin_port, destination_port)
           else
             warn "Error: Invalid criteria '#{criteria}'"
             exit(1)
           end

  if result.empty?
    warn "No routes found from #{origin_port} to #{destination_port} with criteria '#{criteria}'."
    exit(0)
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
rescue RouteFinder::Errors::ApplicationError => e
  warn "Application error: #{e.message}"
  exit(1)
rescue StandardError => e
  warn "Unexpected error: #{e.message}"
  warn e.backtrace.join("\n") if ENV['DEBUG'] == 'true'
  exit(1)
end

# Reads and validates a port code from input
def read_and_validate_port_code(type)
  port_code = gets&.chomp

  begin
    RouteFinder::Validators::PortCodeValidator.validate!(port_code, type)
    port_code
  rescue RouteFinder::Errors::ValidationError => e
    warn "Error: #{e.message}"
    exit(1)
  end
end

# Validates that criteria is one of the accepted values
def read_and_validate_criteria
  criteria = gets&.chomp

  if criteria.nil? || criteria.empty?
    warn 'Error: Missing criteria.'
    exit(1)
  end

  valid_criteria = %w[cheapest-direct cheapest fastest]
  unless valid_criteria.include?(criteria)
    warn "Error: Invalid criteria '#{criteria}'. Valid options are: #{valid_criteria.join(', ')}"
    exit(1)
  end

  criteria
end

# Run the application if this file is executed directly
main if __FILE__ == $PROGRAM_NAME
