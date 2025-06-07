#!/usr/bin/env ruby
require 'json'

# Check if the performance_test_data.json file exists
file_path = File.join(File.dirname(__FILE__), 'performance_test_data.json')
unless File.exist?(file_path)
  puts "File not found: #{file_path}"
  exit 1
end

# Get the file size
file_size = File.size(file_path) / 1024.0 / 1024.0
puts "File exists and is #{file_size.round(2)} MB"

# Read and parse the JSON data
begin
  data = JSON.parse(File.read(file_path))
  puts 'Successfully parsed JSON data'
rescue JSON::ParserError => e
  puts "Failed to parse JSON: #{e.message}"
  exit 1
end

# Output statistics about the data
puts 'Data structure:'
puts "- #{data['sailings'].length} sailings"
puts "- #{data['rates'].length} rates"
puts "- #{data['exchange_rates'].keys.length} days of exchange rates"

# Check some sample data
if data['sailings'].any?
  puts "\nSample sailing:"
  puts data['sailings'].first.inspect
end

if data['rates'].any?
  puts "\nSample rate:"
  puts data['rates'].first.inspect
end

if data['exchange_rates'].any?
  puts "\nSample exchange rate:"
  date = data['exchange_rates'].keys.first
  puts "#{date}: #{data['exchange_rates'][date].inspect}"
end

puts "\nData validation successful"
