# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ApplyTaxesService, type: :service do
  subject(:apply_service) { described_class.new(fee:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee) { create(:fee, invoice:, amount_cents: 1000) }

  let(:tax1) { create(:tax, organization:, rate: 10) }
  let(:tax2) { create(:tax, organization:, rate: 12) }
  let(:tax3) { create(:tax, organization:, rate: 5, applied_to_organization: true) }

  let(:applied_tax1) { create(:applied_tax, customer:, tax: tax1) }
  let(:applied_tax2) { create(:applied_tax, customer:, tax: tax2) }

  before do
    applied_tax1
    applied_tax2
    tax3
  end

  describe 'call' do
    it 'creates fees_taxes' do
      result = apply_service.call

      aggregate_failures do
        expect(result).to be_success

        fees_taxes = result.fees_taxes
        expect(fees_taxes.count).to eq(2)

        expect(fees_taxes[0]).to have_attributes(
          fee:,
          tax: tax1,
          tax_description: tax1.description,
          tax_code: tax1.code,
          tax_name: tax1.name,
          tax_rate: 10,
          amount_currency: fee.currency,
          amount_cents: 100,
        )

        expect(fees_taxes[1]).to have_attributes(
          fee:,
          tax: tax2,
          tax_description: tax2.description,
          tax_code: tax2.code,
          tax_name: tax2.name,
          tax_rate: 12,
          amount_currency: fee.currency,
          amount_cents: 120,
        )

        expect(fee).to have_attributes(
          taxes_amount_cents: 220,
          taxes_rate: 22,
        )
      end
    end

    context 'when customer does not have applied_taxes' do
      let(:applied_tax1) { nil }
      let(:applied_tax2) { nil }

      it 'creates fees_taxes based on the organization taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          fees_taxes = result.fees_taxes
          expect(fees_taxes.count).to eq(1)

          expect(fees_taxes[0]).to have_attributes(
            fee:,
            tax: tax3,
            tax_description: tax3.description,
            tax_code: tax3.code,
            tax_name: tax3.name,
            tax_rate: 5,
            amount_currency: fee.currency,
            amount_cents: 50,
          )

          expect(fee).to have_attributes(
            taxes_amount_cents: 50,
            taxes_rate: 5,
          )
        end
      end
    end
  end
end
