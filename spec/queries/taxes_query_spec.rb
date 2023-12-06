# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxesQuery, type: :query do
  subject(:taxes_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_first) { create(:tax, organization:, name: 'defgh', code: '11') }
  let(:tax_second) { create(:tax, organization:, name: 'abcde', code: '22') }

  let(:tax_third) do
    create(
      :tax,
      organization:,
      name: 'presuv',
      code: '33',
      applied_to_organization: false,
    )
  end

  let(:auto_generated_tax) do
    create(
      :tax,
      organization:,
      name: 'auto_generated',
      code: 'auto_generated',
      rate: 0.0,
      auto_generated: true,
    )
  end

  before do
    tax_first
    tax_second
    tax_third
    auto_generated_tax
  end

  it 'returns all taxes ordered by name asc' do
    result = taxes_query.call(search_term: nil, page: 1, limit: 10)

    expect(result.taxes).to eq([tax_second, auto_generated_tax, tax_first, tax_third])
  end

  context 'when searching for /de/ term' do
    it 'returns only two taxs' do
      result = taxes_query.call(search_term: 'de', page: 1, limit: 10)

      expect(result.taxes).to eq([tax_second, tax_first])
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one tax' do
      result = taxes_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: { ids: [tax_second.id] },
      )

      expect(result.taxes).to eq([tax_second])
    end
  end

  context 'with a filter on applied by default' do
    it 'returns only one tax' do
      result = taxes_query.call(
        search_term: '',
        page: 1,
        limit: 10,
        filters: { applied_to_organization: false },
      )

      expect(result.taxes).to eq([tax_third])
    end
  end

  context 'with a filter on auto generated' do
    it 'returns only one tax' do
      result = taxes_query.call(
        search_term: '',
        page: 1,
        limit: 10,
        filters: { auto_generated: true },
      )

      expect(result.taxes).to eq([auto_generated_tax])
    end
  end

  context 'with order on rate' do
    it 'returns the taxes ordered by rate' do
      result = taxes_query.call(
        search_term: '',
        page: 1,
        limit: 10,
        order: 'rate',
      )

      expect(result.taxes).to eq([auto_generated_tax, tax_first, tax_second, tax_third])
    end
  end
end
