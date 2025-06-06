# frozen_string_literal: true

require 'json'
require_relative './services/route_finder_service'
require_relative './errors/application_error'

module RouteFinder
  class DataLoader
    def initialize(file_path)
      @file_path = file_path
    end

    def load
      # Check if file exists
      raise Errors::FileNotFoundError, "File not found: #{@file_path}" unless File.exist?(@file_path)

      begin
        data = JSON.parse(File.read(@file_path))
      rescue JSON::ParserError => e
        raise Errors::InvalidDataError, "Failed to parse JSON: #{e.message}"
      end

      # Validate required data structures
      validate_data_structure(data)

      {
        sailings: data['sailings'],
        rates: data['rates'],
        exchange_rates: data['exchange_rates']
      }
    end

    # Convenience method to create a RouteFinderService from a JSON file
    def create_service
      data = load
      RouteFinderService.new(data[:sailings], data[:rates], data[:exchange_rates])
    end

    private

    def validate_data_structure(data)
      # Check for required top-level keys
      %w[sailings rates exchange_rates].each do |key|
        unless data.key?(key) && data[key].is_a?(Array)
          raise Errors::InvalidDataError, "Missing or invalid '#{key}' data in JSON file"
        end
      end

      # Validate sailings data
      validate_sailings(data['sailings'])

      # Validate rates data
      validate_rates(data['rates'])

      # Validate exchange_rates data
      validate_exchange_rates(data['exchange_rates'])
    end

    def validate_sailings(sailings)
      return if sailings.empty?

      required_keys = %w[sailing_code origin_port destination_port departure_date arrival_date]

      sailings.each do |sailing|
        next unless sailing.is_a?(Hash)

        missing_keys = required_keys - sailing.keys
        unless missing_keys.empty?
          raise Errors::InvalidDataError, "Missing required fields in sailing data: #{missing_keys.join(', ')}"
        end
      end
    end

    def validate_rates(rates)
      return if rates.empty?

      required_keys = %w[sailing_code rate rate_currency]

      rates.each do |rate|
        next unless rate.is_a?(Hash)

        missing_keys = required_keys - rate.keys
        unless missing_keys.empty?
          raise Errors::InvalidDataError, "Missing required fields in rate data: #{missing_keys.join(', ')}"
        end
      end
    end

    def validate_exchange_rates(exchange_rates)
      return if exchange_rates.empty?

      exchange_rates.each do |date, rates|
        unless date.match?(/^\d{4}-\d{2}-\d{2}$/)
          raise Errors::InvalidDataError, "Invalid date format in exchange rates: #{date}"
        end

        raise Errors::InvalidDataError, "Exchange rates for date #{date} must be a hash/object" unless rates.is_a?(Hash)
      end
    end
  end
end
