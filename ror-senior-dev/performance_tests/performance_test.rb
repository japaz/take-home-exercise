#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'objspace' # For memory tracking
require_relative '../lib/data_loader'

puts "\n=== Performance Testing ==="
puts '1. Using small original dataset (9 sailings)'
puts '2. Using large dataset (~10,000 sailings)'
puts '3. Using massive dataset (~100,000 sailings)'
print 'Select dataset to use [1/2/3]: '
choice = ARGV[0] || '1' # Default to 1 if not provided

# Track initial memory usage
initial_memory = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Initial memory usage: #{initial_memory.round(2)} MB"

# Choose which dataset to use
case choice
when '3'
  ENV['ROUTE_FINDER_DATA_FILE'] = File.join(File.dirname(__FILE__), 'extreme_performance_test_data.json')
  puts 'Using extreme dataset (~250,000 sailings)'
  repetitions = 3 # Very few repetitions for extreme dataset
when '2'
  ENV['ROUTE_FINDER_DATA_FILE'] = File.join(File.dirname(__FILE__), 'performance_test_data.json')
  puts 'Using large dataset (~10,000 sailings)'
  repetitions = 5 # Few repetitions for large dataset
else
  ENV['ROUTE_FINDER_DATA_FILE'] = File.join(File.dirname(File.dirname(__FILE__)), 'response.json')
  puts 'Using original small dataset (9 sailings)'
  repetitions = 100 # More repetitions for small dataset
end

puts "Loading data from: #{RouteFinder::DataLoader.data_file_path}"

# Benchmark data loading with memory tracking
puts "\n=== Benchmarking Data Loading ==="
memory_before_loading = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
data_loading_time = Benchmark.measure do
  @data_loader = RouteFinder::DataLoader.new
  # The line '@data = @data_loader.load' is removed.
end
memory_after_loading = ObjectSpace.memsize_of_all / 1024.0 / 1024.0

puts "Data loaded in: #{(data_loading_time.real * 1000).round(2)} ms"
puts "Memory used for data loading: #{(memory_after_loading - memory_before_loading).round(2)} MB"
# Use attribute readers directly
puts "Loaded #{@data_loader.sailings.length} sailings"
puts "Loaded #{@data_loader.rates.length} rates"
puts "Loaded #{@data_loader.exchange_rates.keys.length} days of exchange rates"

# Benchmark service initialization with memory tracking
puts "\n=== Benchmarking Service Initialization ==="
memory_before_init = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
service_init_time = Benchmark.measure do
  @service = @data_loader.create_service
end
memory_after_init = ObjectSpace.memsize_of_all / 1024.0 / 1024.0

puts "Service initialized in: #{(service_init_time.real * 1000).round(2)} ms"
puts "Memory used for service initialization: #{(memory_after_init - memory_before_init).round(2)} MB"
puts "Total memory usage so far: #{memory_after_init.round(2)} MB"

# Find some real port connections that exist in the data
puts "\nFinding valid port pairs for testing..."
port_connections = {}
# Use attribute reader directly
@data_loader.sailings.each do |sailing|
  origin = sailing['origin_port']
  destination = sailing['destination_port']
  port_connections[origin] ||= []
  port_connections[origin] << destination unless port_connections[origin].include?(destination)
end

# Get a list of ports that have outgoing connections
ports_with_connections = port_connections.keys
puts "Found #{ports_with_connections.length} ports with outgoing connections"

# Select sample origin ports that have connections
num_test_pairs = [5, ports_with_connections.length].min
sample_origins = ports_with_connections.sample(num_test_pairs)
sample_port_pairs = []

# For each origin, find a valid destination
sample_origins.each do |origin|
  next unless port_connections[origin] && !port_connections[origin].empty?

  destination = port_connections[origin].sample
  sample_port_pairs << [origin, destination]
  puts "Selected test pair: #{origin} -> #{destination}"
end

puts "\nRunning each search #{repetitions} times to simulate load"
puts 'Time measurements will be in milliseconds'
puts 'Memory usage will be tracked during searches'

# Helper method to format cost from sailing data
def format_cost(sailing_or_sailings)
  return 'No route found' if sailing_or_sailings.nil? || sailing_or_sailings.empty?

  if sailing_or_sailings.is_a?(Array)
    # For multi-leg routes, sum up the costs
    total_cost = 0
    currency = sailing_or_sailings.first['rate_currency']

    sailing_or_sailings.each do |sailing|
      if sailing['cost_in_cents']
        total_cost += sailing['cost_in_cents']
        currency = sailing['rate_currency']
      elsif sailing['rate']
        # Convert from rate string
        rate_value = sailing['rate'].to_f
        total_cost += (rate_value * 100).to_i
        currency = sailing['rate_currency']
      end
    end

    "#{total_cost / 100.0} #{currency}"
  elsif sailing_or_sailings['cost_in_cents']
    "#{sailing_or_sailings['cost_in_cents'] / 100.0} #{sailing_or_sailings['rate_currency']}"
  else
    "#{sailing_or_sailings['rate']} #{sailing_or_sailings['rate_currency']}"
  end
end

# Helper to calculate duration
def calculate_duration(sailing_or_sailings)
  return 'N/A' if sailing_or_sailings.nil? || sailing_or_sailings.empty?

  if sailing_or_sailings.is_a?(Array)
    if sailing_or_sailings.length == 1
      # Single leg
      (sailing_or_sailings.first['arrival_date_obj'] - sailing_or_sailings.first['departure_date_obj']).to_i
    else
      # Multi-leg: from first departure to last arrival
      first_departure = sailing_or_sailings.first['departure_date_obj']
      last_arrival = sailing_or_sailings.last['arrival_date_obj']
      (last_arrival - first_departure).to_i
    end
  else
    (sailing_or_sailings['arrival_date_obj'] - sailing_or_sailings['departure_date_obj']).to_i
  end
end

# Benchmark cheapest route searches
puts "\n=== Benchmarking Cheapest Route Searches ==="
sample_port_pairs.each do |origin, destination|
  puts "\nSearching cheapest route from #{origin} to #{destination} (#{repetitions} times)"
  total_time = 0
  results = 0
  successful = 0
  memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0

  repetitions.times do |i|
    time = Benchmark.measure do
      result = @service.find_cheapest_route(origin, destination)
      if result && !result.empty?
        successful += 1
        if i == 0 # Only print details for the first run
          puts "Found route with #{result.length} legs, total cost: #{format_cost(result)}"
        end
      end
      results += 1
    rescue StandardError => e
      puts "Error: #{e.message}" if i == 0 # Only print error for the first occurrence
    end
    total_time += time.real
  end

  memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
  memory_used = memory_after - memory_before

  puts "#{successful}/#{results} searches successful"
  puts "Total search time: #{(total_time * 1000).round(2)} ms"
  puts "Average search time: #{(total_time * 1000 / repetitions).round(4)} ms"
  puts "Memory used during search: #{memory_used.round(2)} MB"
end

# Benchmark fastest route searches
puts "\n=== Benchmarking Fastest Route Searches ==="
sample_port_pairs.each do |origin, destination|
  puts "\nSearching fastest route from #{origin} to #{destination} (#{repetitions} times)"
  total_time = 0
  results = 0
  successful = 0
  memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0

  repetitions.times do |i|
    time = Benchmark.measure do
      result = @service.find_fastest_route(origin, destination)
      if result && !result.empty?
        successful += 1
        if i == 0 # Only print details for the first run
          puts "Found route with #{result.length} legs, total duration: #{calculate_duration(result)} days"
        end
      end
      results += 1
    rescue StandardError => e
      puts "Error: #{e.message}" if i == 0 # Only print error for the first occurrence
    end
    total_time += time.real
  end

  memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
  memory_used = memory_after - memory_before

  puts "#{successful}/#{results} searches successful"
  puts "Total search time: #{(total_time * 1000).round(2)} ms"
  puts "Average search time: #{(total_time * 1000 / repetitions).round(4)} ms"
  puts "Memory used during search: #{memory_used.round(2)} MB"
end

# Benchmark direct route searches
puts "\n=== Benchmarking Cheapest Direct Route Searches ==="
sample_port_pairs.each do |origin, destination|
  puts "\nSearching cheapest direct route from #{origin} to #{destination} (#{repetitions} times)"
  total_time = 0
  results = 0
  successful = 0
  memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0

  repetitions.times do |i|
    time = Benchmark.measure do
      result = @service.find_cheapest_direct(origin, destination)
      if result && !result.empty?
        successful += 1
        puts "Found direct route, cost: #{format_cost(result)}" if i == 0 # Only print details for the first run
      end
      results += 1
    rescue StandardError => e
      puts "Error: #{e.message}" if i == 0 # Only print error for the first occurrence
    end
    total_time += time.real
  end

  memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
  memory_used = memory_after - memory_before

  puts "#{successful}/#{results} searches successful"
  puts "Total search time: #{(total_time * 1000).round(2)} ms"
  puts "Average search time: #{(total_time * 1000 / repetitions).round(4)} ms"
  puts "Memory used during search: #{memory_used.round(2)} MB"
end

# Print final memory statistics
memory_final = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "\nFinal memory usage: #{memory_final.round(2)} MB"
puts "Total memory increase since start: #{(memory_final - initial_memory).round(2)} MB"
puts "\nPerformance testing completed!"
