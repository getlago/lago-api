# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LagoEuVat::Rate do
  subject(:rates) { described_class.new }

  describe '.countries_code' do
    it 'returns all EU country codes' do
      countries_code = rates.countries_code

      expect(countries_code.count).to eq(27)
    end
  end

  describe '.country_rate' do
    it 'returns all applicable rates for a country' do
      fr_rates = rates.country_rates(country_code: 'FR')

      aggregate_failures do
        expect(fr_rates['standard']).to eq(20)
      end
    end
  end
end
