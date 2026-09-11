# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ApplyTaxesService do
  subject(:apply_service) { described_class.new(fee:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:billing_entity) { customer.billing_entity }

  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, precise_coupons_amount_cents:) }
  let(:precise_coupons_amount_cents) { 0 }

  let(:tax1) { create(:tax, organization:, rate: 10, applied_to_organization: false) }
  let(:tax2) { create(:tax, organization:, rate: 12, applied_to_organization: false) }
  let(:tax3) { create(:tax, organization:, rate: 5, applied_to_organization: true) }

  before do
    tax1
    tax2
    tax3
    create(:billing_entity_applied_tax, billing_entity:, tax: tax3)
  end

  describe "call" do
    context "when tax_codes parameter" do
      let(:tax_codes) { [tax2.code, tax3.code] }

      it "creates applied_taxes based on the customer taxes" do
        result = described_class.new(fee:, tax_codes:).call

        expect(result).to be_success

        applied_taxes = result.applied_taxes
        expect(applied_taxes.count).to eq(2)

        expect(applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code, tax3.code)
        expect(fee).to have_attributes(taxes_amount_cents: 170, taxes_precise_amount_cents: 170.0, taxes_rate: 17)
      end
    end

    context "when fee is commitment type with taxes" do
      let(:commitment) { create(:commitment, :minimum_commitment, plan:) }
      let(:subscription) { create(:subscription, customer:, plan:) }
      let(:customer) { create(:customer, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:organization) { create(:organization) }

      let(:fee) do
        create(
          :minimum_commitment_fee,
          invoice:,
          amount_cents: 1000,
          precise_amount_cents: 1000.0,
          commitment:,
          subscription:
        )
      end

      before { create(:commitment_applied_tax, commitment:, tax: tax2) }

      it "creates applied_taxes based on the commitment taxes" do
        result = apply_service.call

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
          amount_currency: plan.amount_currency,
          amount_cents: 120,
          precise_amount_cents: 120.0
        )
      end
    end

    context "when fee is add_on type with taxes" do
      let(:add_on) { create(:add_on, organization:) }
      let(:applied_tax2) { create(:add_on_applied_tax, add_on:, tax: tax2) }
      let(:subscription) { create(:subscription, organization:, customer:) }

      let(:fee) do
        create(:add_on_fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, add_on:, subscription:)
      end

      before { applied_tax2 }

      it "creates applied_taxes based on the add_on taxes" do
        result = apply_service.call

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
          precise_amount_cents: 120.0
        )
      end
    end

    context "when fee is a charge type with taxes applied to the plan" do
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, plan:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }

      let(:fee) do
        create(:charge_fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, charge:, subscription:)
      end

      let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }

      before { applied_tax }

      it "creates applied_taxes based on the plan taxes" do
        result = apply_service.call

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
          precise_amount_cents: 100.0
        )
      end

      context "when taxes are applied to the charge" do
        let(:applied_tax2) { create(:charge_applied_tax, charge:, tax: tax2) }

        before { applied_tax2 }

        it "creates applied_taxes based on the plan taxes" do
          result = apply_service.call

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
            precise_amount_cents: 120.0
          )
        end
      end

      context "when fee is a subscription type with taxes applied to the plan" do
        let(:plan) { create(:plan, organization:) }
        let(:subscription) { create(:subscription, organization:, customer:, plan:) }
        let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, subscription:) }
        let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }

        before { applied_tax }

        it "creates applied_taxes based on the plan taxes" do
          result = apply_service.call

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
            precise_amount_cents: 100.0
          )
        end
      end
    end

    context "when customer has applied_taxes" do
      let(:applied_tax1) { create(:customer_applied_tax, customer:, tax: tax1) }
      let(:applied_tax2) { create(:customer_applied_tax, customer:, tax: tax2) }

      before do
        applied_tax1
        applied_tax2
      end

      it "creates applied_taxes based on the customer taxes" do
        result = apply_service.call

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
          precise_amount_cents: 100.0
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
          precise_amount_cents: 120.0
        )

        expect(fee).to have_attributes(
          taxes_amount_cents: 220,
          taxes_precise_amount_cents: 220.0,
          taxes_rate: 22
        )
      end
    end

    context "when a coupon amount is applied to the fee" do
      let(:precise_coupons_amount_cents) { 100 }

      it "takes the coupon amount into account" do
        result = apply_service.call

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
          precise_amount_cents: 45.0
        )

        expect(fee).to have_attributes(
          taxes_amount_cents: 45, # (1000 - 100) * 5 / 100
          taxes_precise_amount_cents: 45.0, # (1000 - 100) * 5 / 100
          taxes_rate: 5
        )
      end
    end

    it "creates applied_taxes based on the billing entity taxes" do
      result = apply_service.call
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
        precise_amount_cents: 50.0
      )

      expect(fee).to have_attributes(
        taxes_amount_cents: 50,
        taxes_precise_amount_cents: 50.0,
        taxes_rate: 5
      )
    end

    context "when fee already have taxes" do
      before { create(:fee_applied_tax, fee:, tax: tax1) }

      it "does not reaply taxes" do
        expect do
          result = apply_service.call

          expect(result).to be_success
        end.not_to change { fee.applied_taxes.count }
      end
    end

    context "when fee is a product type" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }
      let(:product) { create(:product, organization:) }
      let(:rate_card) { create(:rate_card, organization:, product:) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
      let(:rate_card_tax) { create(:tax, organization:, rate: 8) }
      let(:fee) do
        create(
          :product_fee,
          invoice:,
          subscription:,
          rate_card_rate:,
          amount_cents: 1000,
          precise_amount_cents: 1000.0
        )
      end

      it "uses the rate card taxes before the other levels" do
        create(:rate_card_applied_tax, rate_card:, tax: rate_card_tax, organization:)
        create(:plan_applied_tax, plan:, tax: tax2)
        create(:customer_applied_tax, customer:, tax: tax1)

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes).to contain_exactly(
          have_attributes(
            fee:,
            tax: rate_card_tax,
            tax_description: rate_card_tax.description,
            tax_code: rate_card_tax.code,
            tax_name: rate_card_tax.name,
            tax_rate: 8,
            amount_currency: fee.currency,
            amount_cents: 80,
            precise_amount_cents: 80.0
          )
        )
        expect(fee).to have_attributes(taxes_amount_cents: 80, taxes_precise_amount_cents: 80.0, taxes_rate: 8)
      end

      it "falls back to the plan taxes" do
        create(:plan_applied_tax, plan:, tax: tax2)
        create(:customer_applied_tax, customer:, tax: tax1)

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code)
      end

      it "falls back to the customer taxes" do
        create(:customer_applied_tax, customer:, tax: tax1)

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax1.code)
      end

      it "falls back to the billing entity taxes" do
        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax3.code)
      end

      context "when the subscription uses another billing entity" do
        let(:subscription_billing_entity) { create(:billing_entity, organization:) }
        let(:subscription_tax) { create(:tax, organization:, rate: 20) }
        let(:invoice) { create(:invoice, organization:, customer:, billing_entity: subscription_billing_entity) }
        let(:subscription) do
          create(:subscription, organization:, customer:, plan:, billing_entity: subscription_billing_entity)
        end

        before do
          create(
            :billing_entity_applied_tax,
            billing_entity: subscription_billing_entity,
            tax: subscription_tax
          )
        end

        it "falls back to the subscription billing entity taxes" do
          result = apply_service.call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(subscription_tax.code)
        end
      end

      it "applies no taxes when every level is empty" do
        billing_entity.applied_taxes.destroy_all

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes).to be_empty
        expect(fee).to have_attributes(taxes_amount_cents: 0, taxes_precise_amount_cents: 0, taxes_rate: 0)
      end

      it "uses every assigned rate card tax" do
        create(:rate_card_applied_tax, rate_card:, tax: rate_card_tax, organization:)
        create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:)
        create(:plan_applied_tax, plan:, tax: tax2)

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(rate_card_tax.code, tax1.code)
        expect(fee).to have_attributes(taxes_amount_cents: 180, taxes_precise_amount_cents: 180.0, taxes_rate: 18)
      end

      it "treats a zero-percent rate card tax as an override" do
        zero_tax = create(:tax, organization:, rate: 0)
        create(:rate_card_applied_tax, rate_card:, tax: zero_tax, organization:)
        create(:plan_applied_tax, plan:, tax: tax2)

        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(zero_tax.code)
        expect(fee).to have_attributes(taxes_amount_cents: 0, taxes_precise_amount_cents: 0.0, taxes_rate: 0)
      end

      it "uses the next configured level for a replacement fee after removing the rate card override" do
        create(:rate_card_applied_tax, rate_card:, tax: rate_card_tax, organization:)
        create(:plan_applied_tax, plan:, tax: tax2)

        first_result = apply_service.call
        RateCards::ApplyTaxesService.call!(rate_card:, tax_codes: [])

        replacement_fee = create(:product_fee, invoice:, subscription:, rate_card_rate:, amount_cents: 1000)
        replacement_result = described_class.call(fee: replacement_fee)

        expect(first_result.applied_taxes.map(&:tax_code)).to contain_exactly(rate_card_tax.code)
        expect(replacement_result.applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code)
      end

      it "keeps the stored tax snapshot after the invoice is finalized" do
        create(:rate_card_applied_tax, rate_card:, tax: rate_card_tax, organization:)
        apply_service.call
        invoice.update!(status: :finalized)

        RateCards::ApplyTaxesService.call!(rate_card:, tax_codes: [])

        expect(fee.reload.applied_taxes).to contain_exactly(
          have_attributes(
            tax_id: rate_card_tax.id,
            tax_code: rate_card_tax.code,
            tax_name: rate_card_tax.name,
            tax_rate: 8,
            amount_cents: 80,
            precise_amount_cents: 80.0
          )
        )
      end
    end

    context "when fee is a fixed charge type with taxes" do
      let(:fixed_charge) { create(:fixed_charge, organization:) }
      let(:fee) { create(:fixed_charge_fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, fixed_charge:) }
      let(:applied_tax) { create(:fixed_charge_applied_tax, fixed_charge:, tax: tax1) }

      before { applied_tax }

      it "creates applied_taxes based on the fixed charge taxes" do
        result = apply_service.call
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
          precise_amount_cents: 100.0
        )
      end
    end

    context "with explicit customer and plan arguments" do
      let(:other_customer) { create(:customer, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:passed_plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }

      context "when a plan is passed" do
        let(:charge) { create(:standard_charge, plan:) }
        let(:fee) { create(:charge_fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, charge:, subscription:) }

        it "uses the passed plan's taxes, not the subscription plan's" do
          create(:plan_applied_tax, plan:, tax: tax2)
          create(:plan_applied_tax, plan: passed_plan, tax: tax1)

          result = described_class.new(fee:, plan: passed_plan).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax1.code)
        end
      end

      context "when a customer is passed" do
        let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, subscription:) }

        it "uses the passed customer's taxes, not the invoice customer's" do
          create(:customer_applied_tax, customer: other_customer, tax: tax1)

          result = described_class.new(fee:, customer: other_customer).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax1.code)
        end
      end
    end

    context "when customer and plan are passed as nil" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }

      context "when the fee has an invoice" do
        let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, subscription:) }

        it "falls back to the subscription's plan taxes" do
          create(:plan_applied_tax, plan:, tax: tax1)

          result = described_class.new(fee:, customer: nil, plan: nil).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax1.code)
        end

        it "falls back to the invoice customer's taxes" do
          create(:customer_applied_tax, customer:, tax: tax2)

          result = described_class.new(fee:, customer: nil, plan: nil).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code)
        end
      end

      context "when the fee has no invoice" do
        let(:fee) { build(:fee, invoice: nil, amount_cents: 1000, precise_amount_cents: 1000.0, subscription:) }

        it "falls back to the subscription's customer taxes" do
          create(:customer_applied_tax, customer:, tax: tax1)

          result = described_class.new(fee:, customer: nil, plan: nil).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax1.code)
        end

        it "falls back to the subscription's plan taxes" do
          create(:plan_applied_tax, plan:, tax: tax2)

          result = described_class.new(fee:, customer: nil, plan: nil).call

          expect(result).to be_success
          expect(result.applied_taxes.map(&:tax_code)).to contain_exactly(tax2.code)
        end
      end
    end
  end
end
