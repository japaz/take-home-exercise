# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/services/route_finder_service'

RSpec.describe RouteFinder::RouteFinderService do
  let(:sailings) do
    [
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-01',
        'arrival_date' => '2022-03-01', # 28 days
        'sailing_code' => 'ABCD'
      },
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-01-30',
        'arrival_date' => '2022-03-05', # 34 days
        'sailing_code' => 'MNOP'
      },
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-10',
        'arrival_date' => '2022-03-10', # 28 days
        'sailing_code' => 'IJKL'
      },
      # Indirect route legs
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'ESBCN',
        'departure_date' => '2022-01-29',
        'arrival_date' => '2022-02-06', # 8 days
        'sailing_code' => 'ERXQ'
      },
      {
        'origin_port' => 'ESBCN',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-07', # 1 day after previous arrival
        'arrival_date' => '2022-02-15', # 8 days
        'sailing_code' => 'ETRG1'
      },
      {
        'origin_port' => 'ESBCN',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-16', # 10 days after previous arrival
        'arrival_date' => '2022-02-20', # 4 days
        'sailing_code' => 'ETRG'
      },
      # Another indirect route possibility
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'BRSSZ',
        'departure_date' => '2022-01-25',
        'arrival_date' => '2022-02-15', # 21 days
        'sailing_code' => 'XYZK'
      },
      {
        'origin_port' => 'BRSSZ',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-16', # 1 day after previous arrival
        'arrival_date' => '2022-02-25', # 9 days
        'sailing_code' => 'LMNO'
      },
      # One more direct route - faster than others
      {
        'origin_port' => 'CNSHA',
        'destination_port' => 'NLRTM',
        'departure_date' => '2022-02-05',
        'arrival_date' => '2022-02-25', # 20 days - fastest direct
        'sailing_code' => 'FAST'
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
        'sailing_code' => 'ETRG1',
        'rate' => '79.96',
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
      },
      {
        'sailing_code' => 'FAST',
        'rate' => '700.00',
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
      '2022-02-05' => { 'usd' => 1.12, 'jpy' => 129.0 },
      '2022-02-07' => { 'usd' => 1.12, 'jpy' => 129.0 },
      '2022-02-10' => { 'usd' => 1.13, 'jpy' => 130.0 },
      '2022-02-16' => { 'usd' => 1.13, 'jpy' => 130.2 }
    }
  end

  let(:service) { described_class.new(sailings, rates, exchange_rates) }

  describe '#find_fastest_route' do
    context 'when using fastest criteria (TST-0003)' do
      it 'returns the fastest direct sailing if it is the fastest option overall' do
        result = service.find_fastest_route('CNSHA', 'NLRTM')

        expect(result.size).to eq(1)
        expect(result.first).to include(
          'origin_port' => 'CNSHA',
          'destination_port' => 'NLRTM',
          'departure_date' => '2022-02-05',
          'arrival_date' => '2022-02-25',
          'sailing_code' => 'FAST'
        )
      end

      it 'returns the fastest indirect sailing if it is faster than direct options' do
        # Modify sailings to make indirect route faster
        modified_sailings = sailings.reject { |s| s['sailing_code'] == 'FAST' }
        service_without_fast = described_class.new(modified_sailings, rates, exchange_rates)
        
        result = service_without_fast.find_fastest_route('CNSHA', 'NLRTM')

        expect(result.size).to eq(2)
        expect(result[0]).to include(
          'origin_port' => 'CNSHA',
          'destination_port' => 'ESBCN',
          'departure_date' => '2022-01-29',
          'arrival_date' => '2022-02-06'
        )
        expect(result[1]).to include(
          'origin_port' => 'ESBCN',
          'destination_port' => 'NLRTM',
          'departure_date' => '2022-02-07', # Takes the one with earlier departure
          'arrival_date' => '2022-02-15'
        )
        
        # Calculate total days for verification
        dep_date = Date.parse(result[0]['departure_date'])
        arr_date = Date.parse(result[1]['arrival_date'])
        total_days = (arr_date - dep_date).to_i
        
        # The total should be less than any direct option
        expect(total_days).to be < 28 # ABCD or IJKL direct routes (28 days)
      end

      it 'returns empty array when no route exists' do
        result = service.find_fastest_route('CNSHA', 'NONEXISTENT')
        expect(result).to be_empty
      end

      it 'handles routes with more than two legs' do
        additional_sailings = sailings + [
          {
            'origin_port' => 'ESBCN',
            'destination_port' => 'FRPAR', # New intermediate port
            'departure_date' => '2022-02-07',
            'arrival_date' => '2022-02-09', # 2 days
            'sailing_code' => 'BCNPAR'
          },
          {
            'origin_port' => 'FRPAR',
            'destination_port' => 'NLRTM',
            'departure_date' => '2022-02-10', # 1 day after arrival at FRPAR
            'arrival_date' => '2022-02-12', # 2 days
            'sailing_code' => 'PARRTM'
          }
        ]

        additional_rates = rates + [
          {
            'sailing_code' => 'BCNPAR',
            'rate' => '100.00',
            'rate_currency' => 'USD'
          },
          {
            'sailing_code' => 'PARRTM',
            'rate' => '120.00',
            'rate_currency' => 'USD'
          }
        ]

        additional_exchange_rates = exchange_rates.merge({
          '2022-02-10' => { 'usd' => 1.13, 'jpy' => 130.0 }
        })

        service_with_three_legs = described_class.new(additional_sailings, additional_rates, additional_exchange_rates)
        result = service_with_three_legs.find_fastest_route('CNSHA', 'NLRTM')

        # The 3-leg route (CNSHA -> ESBCN -> FRPAR -> NLRTM) should be fastest with total 14 days
        expect(result.size).to eq(3)
        expect(result[0]['sailing_code']).to eq('ERXQ')    # CNSHA -> ESBCN
        expect(result[1]['sailing_code']).to eq('BCNPAR')  # ESBCN -> FRPAR
        expect(result[2]['sailing_code']).to eq('PARRTM')  # FRPAR -> NLRTM
        
        # Calculate total journey time
        dep_date = Date.parse(result[0]['departure_date'])
        arr_date = Date.parse(result[2]['arrival_date'])
        total_days = (arr_date - dep_date).to_i
        
        expect(total_days).to be < 20 # Less than the fastest direct sailing (20 days)
      end
      
      it 'does not select a sailing if its departure_date is before or equal to the previous arrival_date' do
        sailings = [
          {
            'origin_port' => 'USNYC',
            'destination_port' => 'GBLIV',
            'departure_date' => '2022-04-01',
            'arrival_date' => '2022-04-10', # 9 days
            'sailing_code' => 'NYLIV1'
          },
          {
            'origin_port' => 'GBLIV',
            'destination_port' => 'DEHAM',
            'departure_date' => '2022-04-10', # Not valid, same as previous arrival
            'arrival_date' => '2022-04-12', # 2 days
            'sailing_code' => 'LIVHAM1'
          },
          {
            'origin_port' => 'GBLIV',
            'destination_port' => 'DEHAM',
            'departure_date' => '2022-04-11', # Valid, after previous arrival
            'arrival_date' => '2022-04-14', # 3 days
            'sailing_code' => 'LIVHAM2'
          },
          # Direct route is slower (15 days)
          {
            'origin_port' => 'USNYC',
            'destination_port' => 'DEHAM',
            'departure_date' => '2022-04-01',
            'arrival_date' => '2022-04-16',
            'sailing_code' => 'NYHAM'
          }
        ]

        rates = [
          { 'sailing_code' => 'NYLIV1', 'rate' => '200.00', 'rate_currency' => 'USD' },
          { 'sailing_code' => 'LIVHAM1', 'rate' => '50.00', 'rate_currency' => 'USD' }, # Invalid due to date
          { 'sailing_code' => 'LIVHAM2', 'rate' => '60.00', 'rate_currency' => 'USD' },
          { 'sailing_code' => 'NYHAM', 'rate' => '350.00', 'rate_currency' => 'USD' }
        ]

        exchange_rates = {
          '2022-04-01' => { 'usd' => 1.10 },
          '2022-04-10' => { 'usd' => 1.12 },
          '2022-04-11' => { 'usd' => 1.12 }
        }

        service = described_class.new(sailings, rates, exchange_rates)
        result = service.find_fastest_route('USNYC', 'DEHAM')

        expect(result.size).to eq(2)
        expect(result[0]['sailing_code']).to eq('NYLIV1') # First leg
        expect(result[1]['sailing_code']).to eq('LIVHAM2') # Second leg should be LIVHAM2, not LIVHAM1
        
        # Total journey time should be 13 days (9 + 1 layover + 3)
        dep_date = Date.parse(result[0]['departure_date'])
        arr_date = Date.parse(result[1]['arrival_date'])
        total_days = (arr_date - dep_date).to_i
        
        expect(total_days).to be < 15 # Less than the direct route (15 days)
      end
      
      it 'prefers the route with earliest arrival when total journey times are equal' do
        sailings = [
          # Route 1 - earlier departure, same total journey time
          {
            'origin_port' => 'CNSHA',
            'destination_port' => 'NLRTM',
            'departure_date' => '2022-01-01',
            'arrival_date' => '2022-01-20', # 19 days
            'sailing_code' => 'ROUTE1'
          },
          # Route 2 - later departure, same total journey time
          {
            'origin_port' => 'CNSHA',
            'destination_port' => 'NLRTM',
            'departure_date' => '2022-01-05',
            'arrival_date' => '2022-01-24', # 19 days
            'sailing_code' => 'ROUTE2'
          }
        ]

        rates = [
          { 'sailing_code' => 'ROUTE1', 'rate' => '200.00', 'rate_currency' => 'USD' },
          { 'sailing_code' => 'ROUTE2', 'rate' => '220.00', 'rate_currency' => 'USD' }
        ]

        exchange_rates = {
          '2022-01-01' => { 'usd' => 1.10 },
          '2022-01-05' => { 'usd' => 1.10 }
        }

        service = described_class.new(sailings, rates, exchange_rates)
        result = service.find_fastest_route('CNSHA', 'NLRTM')

        expect(result.size).to eq(1)
        expect(result[0]['sailing_code']).to eq('ROUTE1') # Earlier arrival date should be preferred
      end
    end
  end
end
