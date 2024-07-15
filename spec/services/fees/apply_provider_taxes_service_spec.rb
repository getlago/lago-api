# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ApplyProviderTaxesService, type: :service do
  subject(:apply_service) { described_class.new(fee:, fee_taxes:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_coupons_amount_cents:) }
  let(:precise_coupons_amount_cents) { 0 }

  let(:fee_taxes) do
    OpenStruct.new(
      tax_breakdown: [
        OpenStruct.new(name: 'tax 2', type: 'type2', rate: '0.12', tax_amount: 120),
        OpenStruct.new(name: 'tax 3', type: 'type3', rate: '0.05', tax_amount: 50)
      ]
    )
  end

  before do
    fee_taxes
  end

  describe 'call' do
    context 'when there is no applied taxes yet' do
      it 'creates applied_taxes based on the provider taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes.map(&:tax_code)).to contain_exactly('tax_2', 'tax_3')
          expect(fee).to have_attributes(taxes_amount_cents: 170, taxes_rate: 17)
        end
      end
    end

    context 'when fee already have taxes' do
      before { create(:fee_applied_tax, fee:) }

      it 'does not re-apply taxes' do
        expect do
          result = apply_service.call

          expect(result).to be_success
        end.not_to change { fee.applied_taxes.count }
      end
    end
  end
end
