# frozen_string_literal: true

# spec/services/route_finder_service_spec.rb
require_relative '../spec_helper'
require_relative '../../lib/services/route_finder_service'

RSpec.describe RouteFinder::RouteFinderService do
  let(:sailings) do
    [
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-01',
        'arrival_date' => '2022-03-01',
        'sailing_code' => 'ABCD'
      },
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-01-30',
        'arrival_date' => '2022-03-05',
        'sailing_code' => 'MNOP'
      },
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-10',
        'arrival_date' => '2022-03-10',
        'sailing_code' => 'IJKL'
      }
    ]
  end

  let(:rates) do
    [
      {
        'sailing_code' => 'ABCD',
        'rate' => '589.30',
        'rate_currency' => 'USD'
      },
      {
        'sailing_code' => 'MNOP',
        'rate' => '456.78',
        'rate_currency' => 'USD'
      },
      {
        'sailing_code' => 'IJKL',
        'rate' => '97453',
        'rate_currency' => 'JPY'
      }
    ]
  end

  let(:exchange_rates) do
    {
      '2022-02-01' => { 'usd' => 1.126, 'jpy' => 129.5 },
      '2022-01-30' => { 'usd' => 1.1138, 'jpy' => 128.7 },
      '2022-02-10' => { 'usd' => 1.13, 'jpy' => 130.0 }
    }
  end

  let(:service) { described_class.new(sailings, rates, exchange_rates) }

  describe '#find_cheapest_direct' do
    it 'returns the cheapest direct sailing between two ports' do
      result = service.find_cheapest_direct('CNSHA', 'NLRTM')

      expect(result.size).to eq(1)
      expect(result.first).to include(
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'sailing_code' => 'MNOP',
        'rate' => '456.78',
        'rate_currency' => 'USD'
      )
    end

    it 'returns empty array when no direct sailing exists' do
      result = service.find_cheapest_direct('CNSHA', 'BRSSZ')
      expect(result).to be_empty
    end

    it 'excludes sailings without exchange rates' do
      modified_exchange_rates = exchange_rates.dup
      modified_exchange_rates.delete('2022-01-30')

      service_with_missing = described_class.new(sailings, rates, modified_exchange_rates)
      result = service_with_missing.find_cheapest_direct('CNSHA', 'NLRTM')

      expect(result.size).to eq(1)
      expect(result.first['sailing_code']).to eq('ABCD')
    end
  end
end
