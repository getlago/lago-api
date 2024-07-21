# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxesQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, search_term:, filters:, order:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { nil }
  let(:order) { nil }
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
      applied_to_organization: false
    )
  end

  let(:auto_generated_tax) do
    create(
      :tax,
      organization:,
      name: 'auto_generated',
      code: 'auto_generated',
      rate: 0.0,
      auto_generated: true
    )
  end

  before do
    tax_first
    tax_second
    tax_third
    auto_generated_tax
  end

  it 'returns all taxes ordered by name asc' do
    expect(result.taxes).to eq([tax_second, auto_generated_tax, tax_first, tax_third])
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 3} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.taxes.count).to eq(1)
        expect(result.taxes.current_page).to eq(2)
        expect(result.taxes.prev_page).to eq(1)
        expect(result.taxes.next_page).to be_nil
        expect(result.taxes.total_pages).to eq(2)
        expect(result.taxes.total_count).to eq(4)
      end
    end
  end

  context 'when searching for /de/ term' do
    let(:search_term) { 'de' }

    it 'returns only two taxs' do
      expect(result.taxes).to eq([tax_second, tax_first])
    end
  end

  context 'with a filter on applied by default' do
    let(:filters) { {applied_to_organization: false} }

    it 'returns only one tax' do
      expect(result.taxes).to eq([tax_third])
    end
  end

  context 'with a filter on auto generated' do
    let(:filters) { {auto_generated: true} }

    it 'returns only one tax' do
      expect(result.taxes).to eq([auto_generated_tax])
    end
  end

  context 'with order on rate' do
    let(:order) { 'rate' }

    it 'returns the taxes ordered by rate' do
      expect(result.taxes).to eq([auto_generated_tax, tax_first, tax_second, tax_third])
    end
  end
end
