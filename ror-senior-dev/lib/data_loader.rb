# frozen_string_literal: true

require 'json'
require_relative './services/route_finder_service'

module RouteFinder
  class DataLoader
    def initialize(file_path)
      @file_path = file_path
    end

    def load
      data = JSON.parse(File.read(@file_path))
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
  end
end
