#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/data_loader'

data_loader = RouteFinder::DataLoader.new
puts 'Loading data...'
service = data_loader.create_service
puts 'Service initialized.'

# Test origin/destination pairs
pairs = [
  %w[CNSHA NLRTM],
  %w[CNSHA ESBCN],
  %w[ESBCN NLRTM]
]

# Test each method with each pair
puts "\n--- Testing route finding methods ---\n"
pairs.each do |origin, destination|
  puts "\nTesting routes from #{origin} to #{destination}"

  begin
    puts "\nfind_cheapest_direct:"
    result = service.find_cheapest_direct(origin, destination)
    p result
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace[0..2]
  end

  begin
    puts "\nfind_fastest_direct:"
    result = service.find_fastest_direct(origin, destination)
    p result
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace[0..2]
  end

  begin
    puts "\nfind_cheapest_route:"
    result = service.find_cheapest_route(origin, destination)
    p result
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace[0..2]
  end

  begin
    puts "\nfind_fastest_route:"
    result = service.find_fastest_route(origin, destination)
    p result
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace[0..2]
  end
end
