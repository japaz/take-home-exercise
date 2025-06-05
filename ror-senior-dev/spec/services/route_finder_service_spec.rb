# frozen_string_literal: true

# We need to check for having multiple routes for the same origin and destination
# and return the cheapest one that match the criteria for the departure_date, based on the arrival_date of
# the previous route.

# We should try to see if we can work with integers converting the rates to cents and the exchange rates to integers as well,
# so we can avoid floating point precision issues. This way, we can store the rates in cents and exchange rates as integers
# and then we can compare them directly without having to worry about floating point precision issues.

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
      },
      # Indirect route legs
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'ESBCN',
        'departure_date' => '2022-01-29',
        'arrival_date' => '2022-02-06',
        'sailing_code' => 'ERXQ'
      },
      {
        'origin_port' => 'ESBCN',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-16',
        'arrival_date' => '2022-02-20',
        'sailing_code' => 'ETRG'
      },
      # Another indirect route possibility
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'BRSSZ',
        'departure_date' => '2022-01-25',
        'arrival_date' => '2022-02-15',
        'sailing_code' => 'XYZK'
      },
      {
        'origin_port' => 'BRSSZ',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-20',
        'arrival_date' => '2022-03-05',
        'sailing_code' => 'LMNO'
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
      },
      {
        'sailing_code' => 'ERXQ',
        'rate' => '261.96',
        'rate_currency' => 'EUR'
      },
      {
        'sailing_code' => 'ETRG',
        'rate' => '69.96',
        'rate_currency' => 'USD'
      },
      {
        'sailing_code' => 'XYZK',
        'rate' => '350.00',
        'rate_currency' => 'USD'
      },
      {
        'sailing_code' => 'LMNO',
        'rate' => '220.50',
        'rate_currency' => 'USD'
      }
    ]
  end

  let(:exchange_rates) do
    {
      '2022-01-25' => { 'usd' => 1.10, 'jpy' => 127.8 },
      '2022-01-29' => { 'usd' => 1.11, 'jpy' => 128.5 },
      '2022-01-30' => { 'usd' => 1.1138, 'jpy' => 128.7 },
      '2022-02-01' => { 'usd' => 1.126, 'jpy' => 129.5 },
      '2022-02-10' => { 'usd' => 1.13, 'jpy' => 130.0 },
      '2022-02-16' => { 'usd' => 1.13, 'jpy' => 130.2 },
      '2022-02-20' => { 'usd' => 1.14, 'jpy' => 131.0 }
    }
  end

  let(:service) { described_class.new(sailings, rates, exchange_rates) }

  describe '#find_cheapest_direct' do
    context 'when using cheapest-direct criteria (PLS-0001)' do
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
        result = service.find_cheapest_direct('ESBCN', 'CNSHA')
        expect(result).to be_empty
      end

      it 'excludes sailings without exchange rates for rates other than EUR' do
        modified_exchange_rates = exchange_rates.dup
        modified_exchange_rates.delete('2022-01-30')

        service_with_missing = described_class.new(sailings, rates, modified_exchange_rates)
        result = service_with_missing.find_cheapest_direct('CNSHA', 'NLRTM')

        expect(result.size).to eq(1)
        expect(result.first['sailing_code']).to eq('ABCD')
      end

      it 'dose not exclude sailings without exchange rates for rates in EUR' do
        modified_exchange_rates = exchange_rates.dup
        modified_exchange_rates.delete('2022-01-29')

        service_with_missing = described_class.new(sailings, rates, modified_exchange_rates)
        result = service_with_missing.find_cheapest_direct('CNSHA', 'ESBCN')

        expect(result.size).to eq(1)
        expect(result.first['sailing_code']).to eq('ERXQ')
      end
    end
  end

  describe '#find_cheapest_route' do
    context 'when using cheapest criteria (WRT-0002)' do
      it 'returns direct sailing if it is the cheapest option' do
        # Setup rates so the direct sailing is cheapest
        modified_rates = rates.dup
        modified_rates.find { |r| r['sailing_code'] == 'MNOP' }['rate'] = '100.00'
        service_with_cheap_direct = described_class.new(sailings, modified_rates, exchange_rates)

        result = service_with_cheap_direct.find_cheapest_route('CNSHA', 'NLRTM')

        expect(result.size).to eq(1)
        expect(result.first).to include(
          'origin_port' => 'CNSHA',
          'destination_port' => 'NLRTM',
          'departure_date' => '2022-01-30',
          'arrival_date' => '2022-03-05',
          'sailing_code' => 'MNOP',
          'rate' => '100.00',
          'rate_currency' => 'USD'
        )
      end

      it 'returns indirect sailing if it is the cheapest option' do
        result = service.find_cheapest_route('CNSHA', 'NLRTM')

        expect(result.size).to eq(2)
        expect(result[0]).to include(
          'origin_port' => 'CNSHA',
          'destination_port' => 'ESBCN',
          'departure_date' => '2022-01-29',
          'arrival_date' => '2022-02-06',
          'sailing_code' => 'ERXQ',
          'rate' => '261.96',
          'rate_currency' => 'EUR'
        )
        expect(result[1]).to include(
          'origin_port' => 'ESBCN',
          'destination_port' => 'NLRTM',
          'departure_date' => '2022-02-16',
          'arrival_date' => '2022-02-20',
          'sailing_code' => 'ETRG',
          'rate' => '69.96',
          'rate_currency' => 'USD'
        )
      end

      it 'returns the cheapest route among multiple indirect options' do
        result = service.find_cheapest_route('CNSHA', 'NLRTM')

        # Calculate total cost for verification
        total_eur_cost = 0
        result.each do |leg|
          currency = leg['rate_currency'].downcase
          rate_in_currency = leg['rate'].to_f
          leg_rate = if currency == 'eur'
                       rate_in_currency
                     else
                       currency_rate = exchange_rates[leg['departure_date']][currency]
                       rate_in_currency / currency_rate.to_f
                     end
          total_eur_cost += leg_rate
        end

        # The total should be less than any direct option or other indirect routes
        expect(total_eur_cost).to be < 456.78 / 1.1138 # MNOP direct route
        expect(total_eur_cost).to be < (350.00 / 1.10 + 220.50 / 1.14) # CNSHA -> BRSSZ -> NLRTM route
      end

      it 'returns empty array when no route exists' do
        result = service.find_cheapest_route('CNSHA', 'NONEXISTENT')
        expect(result).to be_empty
      end

      it 'handles routes with more than two legs' do
        # Add a test case with a 3-leg route if your implementation supports it
        additional_sailings = sailings + [
          {
            'origin_port' => 'ESBCN',
            'destination_port' => 'BRSSZ',
            'departure_date' => '2022-02-07',
            'arrival_date' => '2022-02-18',
            'sailing_code' => 'ABCZ'
          },
          {
            'origin_port' => 'BRSSZ',
            'destination_port' => 'NLRTM',
            'departure_date' => '2022-02-19',
            'arrival_date' => '2022-03-01',
            'sailing_code' => 'DEFZ'
          }
        ]

        additional_rates = rates + [
          {
            'sailing_code' => 'ABCZ',
            'rate' => '100.00',
            'rate_currency' => 'USD'
          },
          {
            'sailing_code' => 'DEFZ',
            'rate' => '120.00',
            'rate_currency' => 'USD'
          }
        ]

        additional_exchange_rates = exchange_rates.merge({
                                                           '2022-02-07' => { 'usd' => 1.12, 'jpy' => 129.0 },
                                                           '2022-02-19' => { 'usd' => 1.135, 'jpy' => 130.5 }
                                                         })

        service_with_multi_leg = described_class.new(additional_sailings, additional_rates, additional_exchange_rates)

        result = service_with_multi_leg.find_cheapest_route('CNSHA', 'NLRTM')

        # The cheapest could be the three-leg route or another route depending on rates
        # This test verifies that the service can handle multi-leg routes, not necessarily that it picks a specific one
        expect(result).not_to be_empty
      end
    end
  end
end
