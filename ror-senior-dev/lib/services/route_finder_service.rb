# frozen_string_literal: true

module RouteFinder
  class RouteFinderService
    def initialize(data)
      @sailings = data['sailings']
      @rates = data['rates']
      @exchange_rates = data['exchange_rates']
      @rates_by_code = @rates.each_with_object({}) { |r, h| h[r['sailing_code']] = r }
    end

    def find_cheapest_direct(origin, destination)
      min_rate_eur_cents = nil
      cheapest = []

      @sailings.each do |sailing|
        next unless sailing['origin_port'] == origin &&
                    sailing['destination_port'] == destination &&
                    @exchange_rates.key?(sailing['departure_date'])

        rate_info = @rates_by_code[sailing['sailing_code']]
        next unless rate_info

        currency = rate_info['rate_currency'].downcase
        currency_rate = @exchange_rates[sailing['departure_date']][currency]
        next unless currency_rate && currency_rate.to_f > 0

        rate_in_currency = rate_info['rate'].to_f
        rate_eur = rate_in_currency / currency_rate.to_f
        rate_eur_cents = (rate_eur * 100).round

        next unless min_rate_eur_cents.nil? || rate_eur_cents < min_rate_eur_cents

        min_rate_eur_cents = rate_eur_cents
        cheapest = [sailing.merge(
          'rate' => rate_info['rate'],
          'rate_currency' => rate_info['rate_currency'],
          'rate_eur_cents' => rate_eur_cents
        )]
      end

      cheapest
    end
  end
end
