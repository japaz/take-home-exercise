# frozen_string_literal: true

require 'json'
require_relative './services/route_finder_service'
require_relative './errors/application_error'

module RouteFinder
  class DataLoader
    DEFAULT_FILE_PATH = File.join(File.dirname(__FILE__), '../response.json')

    def self.data_file_path
      ENV['ROUTE_FINDER_DATA_FILE'] || DEFAULT_FILE_PATH
    end

    attr_reader :sailings, :rates, :exchange_rates

    def initialize(file_path = nil)
      @file_path = file_path || self.class.data_file_path
      load_data_from_file(@file_path)
    end

    def create_service
      # Directly use instance variables for RouteFinderService instantiation
      RouteFinderService.new(@sailings, @rates, @exchange_rates)
    end

    private

    def load_data_from_file(path_to_load)
      raise Errors::FileNotFoundError, "File not found: #{path_to_load}" unless File.exist?(path_to_load)

      begin
        data = JSON.parse(File.read(path_to_load))
      rescue JSON::ParserError => e
        raise Errors::InvalidDataError, "Failed to parse JSON: #{e.message}"
      end

      validate_data_structure(data) # Call the private instance method for validation

      @sailings = data['sailings']
      @rates = data['rates']
      @exchange_rates = data['exchange_rates']
    end

    def validate_data_structure(data)
      unless data.key?('sailings') && data['sailings'].is_a?(Array)
        raise Errors::InvalidDataError, "Missing or invalid 'sailings' data in JSON file"
      end
      unless data.key?('rates') && data['rates'].is_a?(Array)
        raise Errors::InvalidDataError, "Missing or invalid 'rates' data in JSON file. Expected Array."
      end
      return if data.key?('exchange_rates') && data['exchange_rates'].is_a?(Hash)

      raise Errors::InvalidDataError, "Missing or invalid 'exchange_rates' data in JSON file"
    end
  end
end
