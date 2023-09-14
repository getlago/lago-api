# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ApplyTaxesService, type: :service do
  subject(:apply_service) { described_class.new(fee:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_coupons_amount_cents:) }
  let(:precise_coupons_amount_cents) { 0 }

  let(:tax1) { create(:tax, organization:, rate: 10, applied_to_organization: false) }
  let(:tax2) { create(:tax, organization:, rate: 12, applied_to_organization: false) }
  let(:tax3) { create(:tax, organization:, rate: 5, applied_to_organization: true) }

  before do
    tax1
    tax2
    tax3
  end

  describe 'call' do
    context 'when tax_codes parameter' do
      let(:tax_codes) { [tax2.code, tax3.code] }

      it 'creates applied_taxes based on the customer taxes' do
        result = described_class.new(fee:, tax_codes:).call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code, tax3.code)
          expect(fee).to have_attributes(taxes_amount_cents: 170, taxes_rate: 17)
        end
      end
    end

    context 'when fee is add_on type with taxes' do
      let(:add_on) { create(:add_on, organization:) }
      let(:applied_tax2) { create(:add_on_applied_tax, add_on:, tax: tax2) }
      let(:subscription) { create(:subscription, organization:, customer:) }
      let(:fee) { create(:add_on_fee, invoice:, amount_cents: 1000, add_on:, subscription:) }

      before { applied_tax2 }

      it 'creates applied_taxes based on the add_on taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(1)

          expect(applied_taxes[0]).to have_attributes(
            fee:,
            tax: tax2,
            tax_description: tax2.description,
            tax_code: tax2.code,
            tax_name: tax2.name,
            tax_rate: 12,
            amount_currency: fee.currency,
            amount_cents: 120,
          )
        end
      end
    end

    context 'when fee is a charge type with taxes applied to the plan' do
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, plan:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }

      let(:fee) { create(:charge_fee, invoice:, amount_cents: 1000, charge:, subscription:) }

      let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }

      before { applied_tax }

      it 'creates applied_taxes based on the plan taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(1)

          expect(applied_taxes[0]).to have_attributes(
            fee:,
            tax: tax1,
            tax_description: tax1.description,
            tax_code: tax1.code,
            tax_name: tax1.name,
            tax_rate: 10,
            amount_currency: fee.currency,
            amount_cents: 100,
          )
        end
      end

      context 'when taxes are applied to the charge' do
        let(:applied_tax2) { create(:charge_applied_tax, charge:, tax: tax2) }

        before { applied_tax2 }

        it 'creates applied_taxes based on the plan taxes' do
          result = apply_service.call

          aggregate_failures do
            expect(result).to be_success

            applied_taxes = result.applied_taxes
            expect(applied_taxes.count).to eq(1)

            expect(applied_taxes[0]).to have_attributes(
              fee:,
              tax: tax2,
              tax_description: tax2.description,
              tax_code: tax2.code,
              tax_name: tax2.name,
              tax_rate: 12,
              amount_currency: fee.currency,
              amount_cents: 120,
            )
          end
        end
      end

      context 'when fee is a subscription type with taxes applied to the plan' do
        let(:plan) { create(:plan, organization:) }
        let(:subscription) { create(:subscription, organization:, customer:, plan:) }
        let(:fee) { create(:fee, invoice:, amount_cents: 1000, subscription:) }
        let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }

        before { applied_tax }

        it 'creates applied_taxes based on the plan taxes' do
          result = apply_service.call

          aggregate_failures do
            expect(result).to be_success

            applied_taxes = result.applied_taxes
            expect(applied_taxes.count).to eq(1)

            expect(applied_taxes[0]).to have_attributes(
              fee:,
              tax: tax1,
              tax_description: tax1.description,
              tax_code: tax1.code,
              tax_name: tax1.name,
              tax_rate: 10,
              amount_currency: fee.currency,
              amount_cents: 100,
            )
          end
        end
      end
    end

    context 'when customer has applied_taxes' do
      let(:applied_tax1) { create(:customer_applied_tax, customer:, tax: tax1) }
      let(:applied_tax2) { create(:customer_applied_tax, customer:, tax: tax2) }

      before do
        applied_tax1
        applied_tax2
      end

      it 'creates applied_taxes based on the customer taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes[0]).to have_attributes(
            fee:,
            tax: tax1,
            tax_description: tax1.description,
            tax_code: tax1.code,
            tax_name: tax1.name,
            tax_rate: 10,
            amount_currency: fee.currency,
            amount_cents: 100,
          )

          expect(applied_taxes[1]).to have_attributes(
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
    end

    context 'when a coupon amount is applied to the fee' do
      let(:precise_coupons_amount_cents) { 100 }

      it 'takes the coupon amount into account' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(1)

          expect(applied_taxes[0]).to have_attributes(
            fee:,
            tax: tax3,
            tax_description: tax3.description,
            tax_code: tax3.code,
            tax_name: tax3.name,
            tax_rate: 5,
            amount_currency: fee.currency,
            amount_cents: 45,
          )

          expect(fee).to have_attributes(
            taxes_amount_cents: 45, # (1000 - 100) * 5 / 100
            taxes_rate: 5,
          )
        end
      end
    end

    it 'creates applied_taxes based on the organization taxes' do
      result = apply_service.call

      aggregate_failures do
        expect(result).to be_success

        applied_taxes = result.applied_taxes
        expect(applied_taxes.count).to eq(1)

        expect(applied_taxes[0]).to have_attributes(
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

    context 'when fee already have taxes' do
      before { create(:fee_applied_tax, fee:, tax: tax1) }

      it 'does not reaply taxes' do
        expect do
          result = apply_service.call

          expect(result).to be_success
        end.not_to change { fee.applied_taxes.count }
      end
    end
  end
end
