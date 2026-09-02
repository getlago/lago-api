# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ProcessService do
  describe ".call" do
    subject(:result) { described_class.call(customer:) }

    let(:organization) { create(:organization) }
    let(:customer) do
      create(
        :customer,
        organization:,
        currency: "USD",
        finalize_zero_amount_invoice: customer_finalize_zero_amount_invoice
      )
    end
    let(:customer_finalize_zero_amount_invoice) { "inherit" }
    let(:plan) { create(:plan, organization:, amount_currency: "USD") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:, consolidate_invoice:) }
    let(:consolidate_invoice) { true }
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        customer:,
        subscription:,
        rate_card:,
        units: 5
      )
    end
    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        rate_model:,
        rate_properties:,
        min_amount_cents:
      )
    end
    let(:rate_model) { "standard" }
    let(:rate_properties) { {"amount" => "30.00"} }
    let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "15.00"}) }
    let(:billing_cycle_rate_properties) { {"amount" => "15.00"} }
    let(:billing_cycle_pricing_unit) { nil }
    let(:billing_cycle_proration_ratio) { 1 }
    let(:min_amount_cents) { 0 }

    let!(:billing_cycle) do
      create(
        :billing_cycle,
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        rate_card_rate:,
        rate_override:,
        pricing_unit: billing_cycle_pricing_unit,
        rate_properties: billing_cycle_rate_properties,
        proration_ratio: billing_cycle_proration_ratio,
        billing_at: Time.zone.parse("2026-08-31 23:59:59"),
        period_from: Time.zone.parse("2026-08-01"),
        period_to: Time.zone.parse("2026-08-31 23:59:59")
      )
    end

    describe "#invoice_key" do
      subject(:invoice_key) { service.send(:invoice_key, billing_cycle) }

      let(:service) { described_class.new(customer:) }

      it "returns the invoice grouping key" do
        expect(invoice_key).to eq(
          [
            Date.parse("2026-08-31"),
            :shared,
            "USD",
            customer.billing_entity_id,
            [nil, "provider"],
            nil
          ]
        )
      end

      context "when the customer timezone changes the billing date" do
        before do
          customer.update!(timezone: "America/New_York")
          billing_cycle.update!(billing_at: Time.zone.parse("2026-09-01 02:00:00"))
        end

        it "uses the customer-local billing date" do
          expect(invoice_key.first).to eq(Date.parse("2026-08-31"))
        end
      end

      context "when the subscription opts out of invoice consolidation" do
        let(:consolidate_invoice) { false }

        it "uses the cycle id as the consolidation key" do
          expect(invoice_key[1]).to eq(billing_cycle.id)
        end
      end

      context "when the cycle currency differs from the plan currency" do
        let(:rate_card) { create(:rate_card, organization:, currency: "EUR") }
        let(:plan) { create(:plan, organization:, amount_currency: "USD") }

        it "uses the cycle currency" do
          expect(invoice_key[2]).to eq("EUR")
        end
      end

      context "when the subscription has a billing entity" do
        let(:billing_entity) { create(:billing_entity, organization:) }
        let(:subscription) do
          create(:subscription, organization:, customer:, plan:, consolidate_invoice:, billing_entity:)
        end

        it "uses the subscription billing entity" do
          expect(invoice_key[3]).to eq(billing_entity.id)
        end
      end

      context "when the subscription has a purchase order number" do
        let(:subscription) do
          create(
            :subscription,
            organization:,
            customer:,
            plan:,
            consolidate_invoice:,
            purchase_order_number: "PO-123"
          )
        end

        it "uses the purchase order number" do
          expect(invoice_key[5]).to eq("PO-123")
        end
      end

      context "when the customer has a default payment method" do
        let!(:payment_method) { create(:payment_method, organization:, customer:, is_default: true) }

        it "uses the resolved default payment method" do
          expect(invoice_key[4]).to eq([payment_method.id, "provider"])
        end
      end

      context "when the subscription has an explicit payment method" do
        let(:payment_method) { create(:payment_method, organization:, customer:, is_default: false) }
        let(:subscription) do
          create(
            :subscription,
            organization:,
            customer:,
            plan:,
            consolidate_invoice:,
            payment_method:,
            payment_method_type: "provider"
          )
        end

        before { create(:payment_method, organization:, customer:, is_default: true) }

        it "uses the explicit payment method" do
          expect(invoice_key[4]).to eq([payment_method.id, "provider"])
        end
      end

      context "when the subscription payment method is manual" do
        let(:subscription) do
          create(
            :subscription,
            organization:,
            customer:,
            plan:,
            consolidate_invoice:,
            payment_method_type: "manual"
          )
        end

        before { create(:payment_method, organization:, customer:, is_default: true) }

        it "uses the manual payment method key" do
          expect(invoice_key[4]).to eq([nil, "manual"])
        end
      end

      context "when there is no explicit or default payment method" do
        it "uses the subscription payment method type without an id" do
          expect(invoice_key[4]).to eq([nil, "provider"])
        end
      end
    end

    it "prices the fee from the billing cycle rate override" do
      rate_override.update!(rate_properties: {"amount" => "20.00"})

      expect(result).to be_success

      invoice = result.invoices.sole
      fee = invoice.fees.sole

      expect(fee.amount_cents).to eq(7_500)
      expect(fee.unit_amount_cents).to eq(1_500)
      expect(fee.precise_unit_amount).to eq(15)
      expect(fee.rate_card_rate).to eq(rate_card_rate)
      expect(fee.rate_override).to eq(rate_override)
    end

    context "with a minimum amount above the fee amount" do
      let(:rate_override) { nil }
      let(:billing_cycle_rate_properties) { {"amount" => "10.00"} }
      let(:min_amount_cents) { 10_000 }

      it "persists the fee and its true-up fee" do
        expect(result).to be_success

        invoice = result.invoices.sole
        fee, true_up_fee = invoice.fees.order(:created_at)
        expect(invoice.total_amount_cents).to eq(10_000)
        expect(fee.amount_cents).to eq(5_000)
        expect(true_up_fee).to have_attributes(
          amount_cents: 5_000,
          true_up_parent_fee_id: fee.id
        )
      end
    end

    context "with a fixed product graduated rate" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD", product: create(:product, :fixed, organization:)) }
      let(:rate_model) { "graduated" }
      let(:rate_override) { nil }
      let(:rate_properties) do
        {
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]
        }
      end
      let(:billing_cycle_rate_properties) { rate_properties }

      it "persists the tiered fee on the finalized invoice" do
        expect(result).to be_success

        invoice = result.invoices.sole
        fee = invoice.fees.sole
        expect(invoice.total_amount_cents).to eq(4_200)
        expect(fee).to have_attributes(
          amount_cents: 4_200,
          unit_amount_cents: 840,
          precise_unit_amount: 8.4
        )
        expect(fee.amount_details["graduated_ranges"].size).to eq(2)
      end
    end

    context "with a fixed product volume rate" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD", product: create(:product, :fixed, organization:)) }
      let(:rate_model) { "volume" }
      let(:rate_override) { nil }
      let(:rate_properties) do
        {
          "volume_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]
        }
      end
      let(:billing_cycle_rate_properties) { rate_properties }

      it "persists the tiered fee on the finalized invoice" do
        expect(result).to be_success

        invoice = result.invoices.sole
        fee = invoice.fees.sole
        expect(invoice.total_amount_cents).to eq(3_000)
        expect(fee).to have_attributes(
          amount_cents: 3_000,
          unit_amount_cents: 600,
          precise_unit_amount: 6
        )
        expect(fee.amount_details["per_unit_total_amount"]).to eq("30.0")
      end
    end

    context "with minimum amounts across rate models" do
      let(:rate_override) { nil }
      let(:min_amount_cents) { 10_000 }

      shared_examples "persists the minimum true-up" do |expected_base_amount_cents|
        it "persists the fee and linked true-up fee" do
          expect(result).to be_success

          invoice = result.invoices.sole
          fee, true_up_fee = invoice.fees.order(:created_at)
          expect(invoice.total_amount_cents).to eq(10_000)
          expect(fee.amount_cents).to eq(expected_base_amount_cents)
          expect(true_up_fee).to have_attributes(
            amount_cents: 10_000 - expected_base_amount_cents,
            true_up_parent_fee_id: fee.id
          )
        end
      end

      context "with a standard rate" do
        let(:rate_properties) { {"amount" => "5.00"} }
        let(:billing_cycle_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 2_500

        context "when the fee reaches the floor" do
          let(:rate_properties) { {"amount" => "20.00"} }

          it "does not create a true-up fee" do
            expect(result).to be_success

            invoice = result.invoices.sole
            fee = invoice.fees.sole
            expect(invoice.total_amount_cents).to eq(10_000)
            expect(fee.amount_cents).to eq(10_000)
            expect(fee.true_up_parent_fee_id).to be_nil
          end
        end

        context "with a prorated period" do
          let(:billing_cycle_proration_ratio) { 0.75 }

          it "persists a true-up to the prorated floor" do
            expect(result).to be_success

            invoice = result.invoices.sole
            fee, true_up_fee = invoice.fees.order(:created_at)
            expect(invoice.total_amount_cents).to eq(7_500)
            expect(fee.amount_cents).to eq(1_875)
            expect(true_up_fee).to have_attributes(
              amount_cents: 5_625,
              true_up_parent_fee_id: fee.id
            )
          end
        end
      end

      context "with a graduated rate" do
        let(:rate_model) { "graduated" }
        let(:rate_properties) do
          {
            "graduated_ranges" => [
              {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
              {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
            ]
          }
        end
        let(:billing_cycle_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 4_200
      end

      context "with a volume rate" do
        let(:rate_model) { "volume" }
        let(:rate_properties) do
          {
            "volume_ranges" => [
              {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
              {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
            ]
          }
        end
        let(:billing_cycle_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 3_000
      end
    end

    context "when a scheduled cycle has a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) do
        create(
          :rate_card,
          organization:,
          currency: "USD",
          applied_pricing_unit_code: pricing_unit.code
        )
      end
      let(:rate_card_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          rate_properties: {"amount" => "10.00"},
          applied_pricing_unit_conversion_rate: 0.5
        )
      end
      let(:rate_override) { nil }
      let(:billing_cycle_rate_properties) { {"amount" => "10.00"} }
      let(:billing_cycle_pricing_unit) { pricing_unit }

      before { pricing_unit }

      it "uses the cycle pricing unit to compute the fee" do
        expect(result).to be_success

        fee = result.invoices.sole.fees.sole
        expect(fee.amount_cents).to eq(2_500)
        expect(fee.pricing_unit_usage).to have_attributes(
          pricing_unit:,
          amount_cents: 5_000,
          conversion_rate: 0.5
        )
      end
    end

    context "with multiple cycles due on the same billing date" do
      let(:second_rate_card) { create(:rate_card, organization:, currency: "USD") }
      let(:second_subscription_rate_card) do
        create(
          :subscription_rate_card,
          organization:,
          customer:,
          subscription:,
          rate_card: second_rate_card,
          units: 3
        )
      end
      let(:second_rate_card_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card: second_rate_card,
          rate_properties: {"amount" => "20.00"}
        )
      end

      before do
        create(
          :billing_cycle,
          organization:,
          subscription:,
          customer:,
          subscription_rate_card: second_subscription_rate_card,
          rate_card_rate: second_rate_card_rate,
          rate_properties: {"amount" => "20.00"},
          billing_at: Time.zone.parse("2026-08-31 10:00:00"),
          period_from: Time.zone.parse("2026-08-01"),
          period_to: Time.zone.parse("2026-08-31 23:59:59")
        )
      end

      it "consolidates same-date cycles into one invoice" do
        expect(result).to be_success

        invoice = result.invoices.sole.reload
        expect(invoice.fees.count).to eq(2)
        expect(BillingCycle.where(customer:).distinct.pluck(:invoice_id)).to eq([invoice.id])
      end

      context "when the subscription opts out of invoice consolidation" do
        let(:consolidate_invoice) { false }

        it "creates one invoice per cycle" do
          expect(result).to be_success

          invoices = result.invoices.map(&:reload)
          expect(invoices.count).to eq(2)
          expect(invoices.map { |invoice| invoice.fees.count }).to eq([1, 1])
          expect(BillingCycle.where(customer:).pluck(:invoice_id)).to match_array(invoices.map(&:id))
        end
      end
    end

    context "with a zero amount cycle" do
      let(:rate_override) { nil }
      let(:rate_properties) { {"amount" => "0.00"} }
      let(:billing_cycle_rate_properties) { rate_properties }

      context "when zero amount invoices should be skipped" do
        let(:customer_finalize_zero_amount_invoice) { "skip" }

        it "closes the invoice" do
          expect(result).to be_success

          invoice = result.invoices.sole.reload
          expect(invoice.status).to eq("closed")
          expect(invoice.number).to include("DRAFT")
        end
      end

      context "when zero amount invoices should be finalized" do
        let(:customer_finalize_zero_amount_invoice) { "finalize" }

        it "finalizes the invoice" do
          expect(result).to be_success

          invoice = result.invoices.sole.reload
          expect(invoice.status).to eq("finalized")
          expect(invoice.number).not_to include("DRAFT")
        end
      end
    end
  end
end
