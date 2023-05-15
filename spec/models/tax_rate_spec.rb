# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxRate, type: :model do
  subject(:tax_rate) { create(:tax_rate, applied_by_default:) }

  let(:applied_by_default) { false }

  it_behaves_like 'paper_trail traceable'

  describe 'customers_count' do
    let(:customer) { create(:customer, organization: tax_rate.organization) }

    before { create(:applied_tax_rate, customer:, tax_rate:) }

    it 'returns the number of attached customer' do
      expect(tax_rate.customers_count).to eq(1)
    end

    context 'when tax rate is applied by default' do
      let(:applied_by_default) { true }

      before { create(:customer, organization: tax_rate.organization) }

      it 'returns the number of customer without tax rate' do
        expect(tax_rate.customers_count).to eq(2)
      end
    end
  end
end
