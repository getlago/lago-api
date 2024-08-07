# frozen_string_literal: true

module LagoEuVat
  class Rate
    def initialize
      file_path = Rails.root.join('lib/lago_eu_vat/lago_eu_vat/eu_vat_rates.json')
      json_file = File.read(file_path)
      @json_countries_rates = JSON.parse(json_file)['items']
    end

    def countries_code
      json_countries_rates.map { |country_code, _| country_code }
    end

    def country_rates(country_code:)
      # NOTE: country rates are ordered by date, so we select the most recent applicable
      country_rates = json_countries_rates[country_code].select do |period|
        Time.zone.now >= DateTime.parse(period['effective_from'])
      end

      rates = country_rates.first.fetch('rates')
      exceptions = country_rates.first.fetch('exceptions', [])

      { rates:, exceptions: }
    end

    private

    attr_reader :json_countries_rates
  end
end
