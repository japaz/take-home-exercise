#!/usr/bin/env ruby
require 'json'
require 'date'
require 'benchmark'
require 'objspace'

# Configuration - more reasonable size but still challenging
num_ports = 3000
num_sailings = 250_000
start_date = Date.new(2022, 1, 1)
end_date = Date.new(2025, 6, 6)
currencies = %w[USD EUR JPY]
output_file = 'extreme_performance_test_data.json'

puts 'Starting to generate large-scale performance test dataset...'
puts "- #{num_ports} ports"
puts "- #{num_sailings} sailings"
puts "- Date range: #{start_date} to #{end_date}"
puts "- Output file: #{output_file}"
puts '- Memory optimization enabled'

# Initialize memory tracking
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Initial memory usage: #{memory_before.round(2)} MB"

# Generate port codes efficiently
puts "\nGenerating port codes..."
country_codes = %w[US CN JP GB DE FR ES IT BR AU CA IN SG NL BE ZA MX RU AE EG KR MY TH VN ID PH TR ZW AR CL CO PE NG
                   EG DK SE NO FI]
location_letters = ('A'..'Z').to_a

port_codes = Set.new
port_gen_time = Benchmark.measure do
  while port_codes.size < num_ports
    country = country_codes.sample
    location = Array.new(3) { location_letters.sample }.join
    port_codes.add("#{country}#{location}")
  end
end

port_codes = port_codes.to_a
memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
puts "Generated #{port_codes.length} unique port codes in #{(port_gen_time.real * 1000).round(2)} ms"
puts "Memory used for port codes: #{(memory_after - memory_before).round(2)} MB"

# Generate hub ports for complex routes
hub_count = [port_codes.length / 100, 30].min # About 1% of ports as hubs, up to 30
hub_ports = port_codes.sample(hub_count)
puts "Designated #{hub_count} ports as transportation hubs for complex routes"

# Write sailings directly to file to save memory
puts "\nStreaming sailings directly to file..."
memory_before = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
seen_codes = Set.new

sailing_gen_time = Benchmark.measure do
  File.open(output_file, 'w') do |f|
    f.write("{\n")
    f.write("  \"sailings\": [\n")

    # Generate direct sailings (70% of total)
    direct_count = (num_sailings * 0.7).to_i
    puts "Generating #{direct_count} direct sailings..."

    direct_count.times do |i|
      origin = port_codes.sample
      destination = port_codes.reject { |p| p == origin }.sample

      departure_date_obj = start_date + rand(0..(end_date - start_date)).to_i
      departure_date = departure_date_obj.to_s
      travel_days = rand(3..60) # Varying travel times
      arrival_date_obj = departure_date_obj + travel_days
      arrival_date = arrival_date_obj.to_s

      # Generate unique sailing code
      sailing_code = nil
      loop do
        sailing_code = Array.new(4) { location_letters.sample }.join
        break unless seen_codes.include?(sailing_code)
      end
      seen_codes.add(sailing_code)

      sailing = {
        'origin_port' => origin,
        'destination_port' => destination,
        'departure_date' => departure_date,
        'arrival_date' => arrival_date,
        'sailing_code' => sailing_code
      }

      f.write("    #{sailing.to_json}")
      f.write(i < num_sailings - 1 ? ",\n" : "\n") # Always add comma except for last sailing

      # Print progress at intervals
      if (i + 1) % 50_000 == 0
        memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
        puts "Generated #{i + 1} direct sailings... Memory usage: #{memory_current.round(2)} MB"
      end
    end

    # Generate hub-connected sailings (30% of total)
    hub_sailings_count = (num_sailings * 0.3).to_i
    puts "Generating #{hub_sailings_count} hub-connected sailings..."

    hub_sailings_count.times do |i|
      hub = hub_ports.sample

      # Sailings to hub
      origin = port_codes.reject { |p| p == hub || hub_ports.include?(p) }.sample
      departure_date_obj = start_date + rand(0..(end_date - start_date - 60)).to_i
      departure_date = departure_date_obj.to_s
      travel_days = rand(3..30)
      arrival_date_obj = departure_date_obj + travel_days
      arrival_date = arrival_date_obj.to_s

      # Generate unique sailing code
      sailing_code = nil
      loop do
        sailing_code = Array.new(4) { location_letters.sample }.join
        break unless seen_codes.include?(sailing_code)
      end
      seen_codes.add(sailing_code)

      sailing = {
        'origin_port' => origin,
        'destination_port' => hub,
        'departure_date' => departure_date,
        'arrival_date' => arrival_date,
        'sailing_code' => sailing_code
      }

      f.write("    #{sailing.to_json},\n")

      # Sailings from hub to destination
      destination = port_codes.reject { |p| p == hub || p == origin || hub_ports.include?(p) }.sample
      departure_date_obj = arrival_date_obj + rand(1..7) # Layover time at hub
      departure_date = departure_date_obj.to_s
      travel_days = rand(3..30)
      arrival_date_obj = departure_date_obj + travel_days
      arrival_date = arrival_date_obj.to_s

      # Generate unique sailing code
      sailing_code = nil
      loop do
        sailing_code = Array.new(4) { location_letters.sample }.join
        break unless seen_codes.include?(sailing_code)
      end
      seen_codes.add(sailing_code)

      sailing = {
        'origin_port' => hub,
        'destination_port' => destination,
        'departure_date' => departure_date,
        'arrival_date' => arrival_date,
        'sailing_code' => sailing_code
      }

      is_last = (i == hub_sailings_count - 1)
      f.write("    #{sailing.to_json}")
      f.write(is_last ? "\n" : ",\n")

      # Print progress at intervals
      if (i + 1) % 25_000 == 0
        memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
        puts "Generated #{(i + 1) * 2} hub-connected sailings... Memory usage: #{memory_current.round(2)} MB"
      end
    end

    f.write("  ],\n")

    # Generate and write rates directly to file
    f.write("  \"rates\": [\n")
    puts "\nGenerating rates and writing them directly to file..."

    seen_codes.each_with_index do |code, i|
      currency = currencies.sample
      rate = if currency == 'JPY'
               rand(10_000..200_000).to_s
             else
               '%.2f' % rand(50.0..2000.0)
             end

      rate_obj = {
        'sailing_code' => code,
        'rate' => rate,
        'rate_currency' => currency
      }

      f.write("    #{rate_obj.to_json}")
      f.write(i < seen_codes.size - 1 ? ",\n" : "\n")

      # Print progress at intervals
      if (i + 1) % 50_000 == 0
        memory_current = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
        puts "Generated #{i + 1} rates... Memory usage: #{memory_current.round(2)} MB"
      end
    end
    f.write("  ],\n")

    # Generate and write exchange rates directly to file
    f.write("  \"exchange_rates\": {\n")
    puts "\nGenerating exchange rates and writing them directly to file..."

    days_total = (end_date - start_date).to_i
    current_date = start_date
    days_processed = 0

    while current_date <= end_date
      date_str = current_date.to_s

      rates = {
        'usd' => (rand(1.0..1.5) * 100).round / 100.0,
        'jpy' => (rand(120.0..160.0) * 100).round / 100.0
      }

      f.write("    \"#{date_str}\": #{rates.to_json}")
      f.write(current_date < end_date ? ",\n" : "\n")

      current_date = current_date.next_day
      days_processed += 1

      # Print progress at intervals
      puts "Generated exchange rates for #{days_processed} days out of #{days_total}..." if days_processed % 400 == 0
    end

    f.write("  }\n")
    f.write("}\n")
  end
end

memory_after = ObjectSpace.memsize_of_all / 1024.0 / 1024.0
file_size_mb = File.size(output_file) / (1024.0 * 1024.0)

puts "\nGeneration completed in #{sailing_gen_time.real.round(2)} seconds"
puts "Memory used: #{(memory_after - memory_before).round(2)} MB"
puts "File size: #{file_size_mb.round(2)} MB"
puts "Generated #{num_sailings + hub_sailings_count} total sailings"
puts "Wrote #{seen_codes.size} rates"
puts "Generated #{days_total} days of exchange rates"
puts "Data written to #{output_file}"
