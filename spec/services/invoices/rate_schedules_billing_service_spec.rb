# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RateSchedulesBillingService do
  subject(:billing_service) do
    described_class.new(subscription_rate_schedules:, timestamp: billing_timestamp)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "EUR") }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, started_at: started_at, subscription_at: started_at, status: :active)
  end
  let(:started_at) { DateTime.new(2026, 1, 1) }
  let(:billing_timestamp) { DateTime.new(2026, 2, 1).to_i }

  let(:product) { create(:product, organization:) }
  let(:subscription_item) { create(:product_item, :subscription, organization:, product:) }
  let(:plan_product) { create(:plan_product, organization:, plan:, product:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item: subscription_item) }
  let(:rate_schedule) do
    create(:rate_schedule,
      organization:,
      plan_product_item:,
      product_item: subscription_item,
      charge_model: "standard",
      billing_interval_unit: "month",
      billing_interval_count: 1,
      amount_currency: "EUR",
      properties: {"amount" => "49.99"},
      position: 0)
  end

  let(:srs) do
    create(:subscription_rate_schedule,
      organization:,
      subscription:,
      rate_schedule:,
      product_item: subscription_item,
      status: :active,
      started_at:,
      intervals_billed: 0,
      next_billing_date: Date.new(2026, 2, 1))
  end

  let(:subscription_rate_schedules) { SubscriptionRateSchedule.where(id: srs.id).includes(:subscription, :rate_schedule, :product_item) }

  before do
    plan_product
  end

  describe "#call" do
    it "creates an invoice with a subscription fee" do
      result = billing_service.call

      expect(result).to be_success

      invoice = result.invoice
      expect(invoice).to be_persisted
      expect(invoice.invoice_type).to eq("subscription")
      expect(invoice.currency).to eq("EUR")
      expect(invoice.fees_amount_cents).to eq(4999)
      expect(invoice.sub_total_excluding_taxes_amount_cents).to eq(4999)
    end

    it "creates an invoice_subscription" do
      billing_service.call

      invoice_subscription = InvoiceSubscription.last
      expect(invoice_subscription.subscription).to eq(subscription)
      expect(invoice_subscription.recurring).to be(true)
      expect(invoice_subscription.invoicing_reason).to eq("subscription_periodic")
    end

    it "creates a product_item fee with correct attributes" do
      result = billing_service.call
      fee = result.invoice.fees.sole

      expect(fee.fee_type).to eq("product_item")
      expect(fee.amount_cents).to eq(4999)
      expect(fee.amount_currency).to eq("EUR")
      expect(fee.units).to eq(1)
      expect(fee.subscription).to eq(subscription)
      expect(fee.subscription_rate_schedule).to eq(srs)
      expect(fee.invoiceable).to eq(subscription_item)
      expect(fee.payment_status).to eq("pending")
      expect(fee.properties).to include("from_datetime" => "2026-01-01", "to_datetime" => "2026-02-01")
    end

    it "advances the subscription_rate_schedule billing state" do
      billing_service.call

      srs.reload
      expect(srs.intervals_billed).to eq(1)
      expect(srs.next_billing_date).to eq(Date.new(2026, 3, 1))
    end

    context "with a fixed item type" do
      let(:fixed_item) { create(:product_item, :fixed, organization:, product:) }
      let(:fixed_ppi) { create(:plan_product_item, organization:, plan:, product_item: fixed_item) }
      let(:fixed_rate_schedule) do
        create(:rate_schedule,
          organization:,
          plan_product_item: fixed_ppi,
          product_item: fixed_item,
          charge_model: "standard",
          billing_interval_unit: "month",
          billing_interval_count: 1,
          amount_currency: "EUR",
          units: 3,
          properties: {"amount" => "10.00"},
          position: 0)
      end

      let(:fixed_srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          rate_schedule: fixed_rate_schedule,
          product_item: fixed_item,
          status: :active,
          started_at:,
          intervals_billed: 0,
          next_billing_date: Date.new(2026, 2, 1))
      end

      let(:subscription_rate_schedules) do
        SubscriptionRateSchedule.where(id: fixed_srs.id).includes(:subscription, :rate_schedule, :product_item)
      end

      it "computes amount as amount * units" do
        result = billing_service.call
        fee = result.invoice.fees.sole

        expect(fee.amount_cents).to eq(3000) # 10.00 * 3 units * 100 subunit
        expect(fee.units).to eq(3)
      end
    end

    context "with multiple subscription_rate_schedules" do
      let(:fixed_item) { create(:product_item, :fixed, organization:, product:) }
      let(:fixed_ppi) { create(:plan_product_item, organization:, plan:, product_item: fixed_item) }
      let(:fixed_rate_schedule) do
        create(:rate_schedule,
          organization:,
          plan_product_item: fixed_ppi,
          product_item: fixed_item,
          charge_model: "standard",
          billing_interval_unit: "month",
          billing_interval_count: 1,
          amount_currency: "EUR",
          units: 1,
          properties: {"amount" => "19.99"},
          position: 0)
      end

      let(:fixed_srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          rate_schedule: fixed_rate_schedule,
          product_item: fixed_item,
          status: :active,
          started_at:,
          intervals_billed: 0,
          next_billing_date: Date.new(2026, 2, 1))
      end

      let(:subscription_rate_schedules) do
        SubscriptionRateSchedule.where(id: [srs.id, fixed_srs.id]).includes(:subscription, :rate_schedule, :product_item)
      end

      it "creates one invoice with multiple fees" do
        result = billing_service.call

        expect(result.invoice.fees.count).to eq(2)
        expect(result.invoice.fees_amount_cents).to eq(4999 + 1999)
      end

      it "creates a single invoice_subscription for the shared subscription" do
        billing_service.call

        expect(InvoiceSubscription.count).to eq(1)
      end
    end

    context "with multiple subscriptions" do
      let(:other_subscription) do
        create(:subscription, organization:, customer:, plan:, started_at:, subscription_at: started_at, status: :active,
          external_id: "other_sub")
      end

      let(:other_srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription: other_subscription,
          rate_schedule:,
          product_item: subscription_item,
          status: :active,
          started_at:,
          intervals_billed: 0,
          next_billing_date: Date.new(2026, 2, 1))
      end

      let(:subscription_rate_schedules) do
        SubscriptionRateSchedule.where(id: [srs.id, other_srs.id]).includes(:subscription, :rate_schedule, :product_item)
      end

      it "creates one invoice_subscription per subscription" do
        billing_service.call

        expect(InvoiceSubscription.count).to eq(2)
        expect(InvoiceSubscription.pluck(:subscription_id)).to match_array([subscription.id, other_subscription.id])
      end
    end

    context "with a grace period" do
      let(:customer) { create(:customer, organization:, currency: "EUR", invoice_grace_period: 3) }

      it "sets invoice status to draft" do
        result = billing_service.call

        expect(result.invoice.status).to eq("draft")
      end
    end

    context "without a grace period" do
      it "transitions invoice to final status" do
        result = billing_service.call

        expect(result.invoice.status).not_to eq("generating")
      end
    end

    context "with a zero-decimal currency (JPY)" do
      let(:customer) { create(:customer, organization:, currency: "JPY") }
      let(:rate_schedule) do
        create(:rate_schedule,
          organization:,
          plan_product_item:,
          product_item: subscription_item,
          charge_model: "standard",
          billing_interval_unit: "month",
          billing_interval_count: 1,
          amount_currency: "JPY",
          properties: {"amount" => "5000"},
          position: 0)
      end

      it "computes amount_cents correctly (subunit_to_unit = 1)" do
        result = billing_service.call
        fee = result.invoice.fees.sole

        expect(fee.amount_cents).to eq(5000)
        expect(fee.amount_currency).to eq("JPY")
      end
    end
  end
end
