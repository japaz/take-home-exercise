#!/usr/bin/env ruby
require 'json'
require 'date'
require 'benchmark'
require 'objspace' # For memory tracking

# Configuration
num_ports = 5000 # Increased to 5000 ports for more route diversity
num_sailings = 1_000_000 # Increased to 1,000,000 sailings
start_date = Date.new(2022, 1, 1)
end_date = Date.new(2025, 6, 6)
currencies = %w[USD EUR JPY]
output_file = 'extreme_performance_test_data.json'

puts 'Starting to generate extreme performance test dataset...'
puts "- #{num_ports} ports"
puts "- #{num_sailings} sailings"
puts "- Date range: #{start_date} to #{end_date}"
puts "- Output file: #{output_file}"
puts '- Memory usage will be tracked during generation'

# Initialize memory tracking
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Initial memory usage: #{memory_before.round(2)} MB"

# Generate port codes with better memory efficiency
puts "\nGenerating port codes..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
country_codes = %w[US CN JP GB DE FR ES IT BR AU CA IN SG NL BE ZA MX RU AE EG KR MY TH VN ID PH TR ZW AR CL CO PE NG
                   EG DK SE NO FI]
location_letters = ('A'..'Z').to_a

port_codes = Set.new # Use a Set for faster uniqueness checks
port_gen_time = Benchmark.measure do
  while port_codes.size < num_ports
    country = country_codes.sample
    location = Array.new(3) { location_letters.sample }.join
    port_codes.add("#{country}#{location}")
  end
end

port_codes = port_codes.to_a # Convert back to array for further processing

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Generated #{port_codes.length} unique port codes in #{(port_gen_time.real * 1000).round(2)} ms"
puts "Memory used for port codes: #{(memory_after - memory_before).round(2)} MB"

# Generate hub ports for complex routes
hub_count = [port_codes.length / 20, 50].min # Use about 5% of ports as hubs, max 50
hub_ports = port_codes.sample(hub_count)
puts "Designated #{hub_count} ports as transportation hubs for complex routes"

# Create common port pairs for consistent routes
common_pairs = []
200.times do
  origin = port_codes.sample
  destination = port_codes.sample
  common_pairs << [origin, destination] unless origin == destination
end
puts 'Created 200 common port pairs for route consistency'

# Generate sailings with progress reporting and memory tracking
puts "\nGenerating sailings..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
sailings = []
sailing_codes = []

# Create a sailing code generator that's more efficient
seen_codes = Set.new
def generate_unique_code(seen, letters)
  code = nil
  loop do
    code = Array.new(4) { letters.sample }.join
    break unless seen.include?(code)
  end
  seen.add(code)
  code
end

sailing_gen_time = Benchmark.measure do
  # Generate direct sailings (70% of total)
  direct_count = (num_sailings * 0.7).to_i
  puts "Generating #{direct_count} direct sailings..."

  direct_count.times do |i|
    # Use common pairs more frequently
    if rand < 0.3 && !common_pairs.empty?
      origin, destination = common_pairs.sample
    else
      origin = port_codes.sample
      destination = port_codes.reject { |p| p == origin }.sample
    end

    departure_date_obj = start_date + rand(0..(end_date - start_date)).to_i
    departure_date = departure_date_obj.to_s
    travel_days = rand(3..60) # Varying travel times
    arrival_date_obj = departure_date_obj + travel_days
    arrival_date = arrival_date_obj.to_s

    sailing_code = generate_unique_code(seen_codes, location_letters)

    sailings << {
      'origin_port' => origin,
      'destination_port' => destination,
      'departure_date' => departure_date,
      'arrival_date' => arrival_date,
      'sailing_code' => sailing_code
    }

    # Print progress at intervals
    if (i + 1) % 100_000 == 0
      memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
      puts "Generated #{i + 1} direct sailings... Memory usage: #{memory_current.round(2)} MB"
    end
  end

  # Generate hub-connected sailings (30% of total)
  hub_count = (num_sailings * 0.3).to_i
  puts "Generating #{hub_count} hub-connected sailings..."

  hub_count.times do |i|
    hub = hub_ports.sample

    # Sailings to hub
    origin = port_codes.reject { |p| p == hub || hub_ports.include?(p) }.sample
    departure_date_obj = start_date + rand(0..(end_date - start_date - 60)).to_i
    departure_date = departure_date_obj.to_s
    travel_days = rand(3..30)
    arrival_date_obj = departure_date_obj + travel_days
    arrival_date = arrival_date_obj.to_s

    sailing_code = generate_unique_code(seen_codes, location_letters)

    sailings << {
      'origin_port' => origin,
      'destination_port' => hub,
      'departure_date' => departure_date,
      'arrival_date' => arrival_date,
      'sailing_code' => sailing_code
    }

    # Sailings from hub to destination
    destination = port_codes.reject { |p| p == hub || p == origin || hub_ports.include?(p) }.sample
    departure_date_obj = arrival_date_obj + rand(1..10) # Layover time at hub
    departure_date = departure_date_obj.to_s
    travel_days = rand(3..30)
    arrival_date_obj = departure_date_obj + travel_days
    arrival_date = arrival_date_obj.to_s

    sailing_code = generate_unique_code(seen_codes, location_letters)

    sailings << {
      'origin_port' => hub,
      'destination_port' => destination,
      'departure_date' => departure_date,
      'arrival_date' => arrival_date,
      'sailing_code' => sailing_code
    }

    # Print progress at intervals
    if (i + 1) % 50_000 == 0
      memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
      puts "Generated #{(i + 1) * 2} hub-connected sailings... Memory usage: #{memory_current.round(2)} MB"
    end
  end

  # Get all sailing codes
  sailing_codes = sailings.map { |s| s['sailing_code'] }
end

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Generated #{sailings.length} sailings in #{sailing_gen_time.real.round(2)} seconds"
puts "Memory used for sailings: #{(memory_after - memory_before).round(2)} MB"

# Generate rates with progress reporting
puts "\nGenerating rates..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
rates = []

rates_gen_time = Benchmark.measure do
  sailing_codes.each_with_index do |code, i|
    currency = currencies.sample
    rate = if currency == 'JPY'
             rand(10_000..200_000).to_s
           else
             '%.2f' % rand(50.0..2000.0)
           end

    rates << {
      'sailing_code' => code,
      'rate' => rate,
      'rate_currency' => currency
    }

    # Print progress at intervals
    if (i + 1) % 100_000 == 0
      memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
      puts "Generated #{i + 1} rates... Memory usage: #{memory_current.round(2)} MB"
    end
  end
end

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Generated #{rates.length} rates in #{rates_gen_time.real.round(2)} seconds"
puts "Memory used for rates: #{(memory_after - memory_before).round(2)} MB"

# Generate exchange rates with progress reporting
puts "\nGenerating exchange rates..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
exchange_rates = {}
days_total = (end_date - start_date).to_i

exchange_rates_gen_time = Benchmark.measure do
  current_date = start_date
  days_processed = 0

  while current_date <= end_date
    date_str = current_date.to_s

    exchange_rates[date_str] = {
      'usd' => (rand(1.0..1.5) * 100).round / 100.0,
      'jpy' => (rand(120.0..160.0) * 100).round / 100.0
    }

    current_date = current_date.next_day
    days_processed += 1

    # Print progress at intervals
    puts "Generated exchange rates for #{days_processed} days out of #{days_total}..." if days_processed % 200 == 0
  end
end

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Generated exchange rates for #{exchange_rates.keys.length} dates in #{exchange_rates_gen_time.real.round(2)} seconds"
puts "Memory used for exchange rates: #{(memory_after - memory_before).round(2)} MB"

# Write to file with memory monitoring and streaming to avoid memory spikes
puts "\nWriting data to file (streaming to manage memory)..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
file_write_time = Benchmark.measure do
  File.open(output_file, 'w') do |f|
    f.write("{\n")

    # Write sailings
    f.write("  \"sailings\": [\n")
    sailings.each_with_index do |sailing, i|
      f.write("    #{sailing.to_json}")
      f.write(i < sailings.length - 1 ? ",\n" : "\n")

      # Report progress periodically
      puts "Written #{i + 1}/#{sailings.length} sailings..." if (i + 1) % 200_000 == 0
    end
    f.write("  ],\n")

    puts 'Written all sailings, writing rates...'

    # Write rates
    f.write("  \"rates\": [\n")
    rates.each_with_index do |rate, i|
      f.write("    #{rate.to_json}")
      f.write(i < rates.length - 1 ? ",\n" : "\n")

      # Report progress periodically
      puts "Written #{i + 1}/#{rates.length} rates..." if (i + 1) % 200_000 == 0
    end
    f.write("  ],\n")

    puts 'Written all rates, writing exchange rates...'

    # Write exchange rates
    f.write("  \"exchange_rates\": {\n")
    exchange_rates.each_with_index do |(date, rate), i|
      f.write("    \"#{date}\": #{rate.to_json}")
      f.write(i < exchange_rates.length - 1 ? ",\n" : "\n")

      # Report progress periodically
      puts "Written #{i + 1}/#{exchange_rates.length} exchange rates..." if (i + 1) % 300 == 0
    end
    f.write("  }\n")

    f.write("}\n")
  end
end

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Data written to #{output_file} in #{file_write_time.real.round(2)} seconds"
puts "Memory used during file write: #{(memory_after - memory_before).round(2)} MB"

file_size_mb = File.size(output_file) / (1024.0 * 1024.0)
puts "Final file size: #{file_size_mb.round(2)} MB"

# Print total time and memory used
puts "\nTotal memory usage: #{(ObjectSpace.memsize_of_all / 1024.0 / 1024.0).round(2)} MB"
puts 'Generation complete!'
