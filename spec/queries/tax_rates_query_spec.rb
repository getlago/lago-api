# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxRatesQuery, type: :query do
  subject(:tax_rates_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate_first) { create(:tax_rate, organization:, name: 'defgh', code: '11') }
  let(:tax_rate_second) { create(:tax_rate, organization:, name: 'abcde', code: '22') }
  let(:tax_rate_third) { create(:tax_rate, organization:, name: 'presuv', code: '33') }

  before do
    tax_rate_first
    tax_rate_second
    tax_rate_third
  end

  it 'returns all tax_rates ordered by name asc' do
    result = tax_rates_query.call(search_term: nil, page: 1, limit: 10)

    expect(result.tax_rates).to eq([tax_rate_second, tax_rate_first, tax_rate_third])
  end

  context 'when searching for /de/ term' do
    it 'returns only two tax_rates' do
      result = tax_rates_query.call(search_term: 'de', page: 1, limit: 10)

      expect(result.tax_rates).to eq([tax_rate_second, tax_rate_first])
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one tax_rate' do
      result = tax_rates_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: { ids: [tax_rate_second.id] },
      )

      expect(result.tax_rates).to eq([tax_rate_second])
    end
  end
end
