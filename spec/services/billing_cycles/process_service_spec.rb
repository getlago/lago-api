# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ProcessService do
  subject(:result) { described_class.call(subscription:, billing_at:) }

  let(:billing_at) { Time.utc(2026, 7, 1) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_currency: "USD") }
  let(:product_item) { create(:product_item, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:, currency: "USD", proration: "full") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }

  let(:subscription_product_item) do
    create(:subscription_product_item, organization:, subscription:, product_item:,
      billing_anchor_date: Date.new(2026, 6, 1), started_at: Time.utc(2026, 6, 1), next_billing_at: Time.utc(2026, 7, 1))
  end

  let!(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item:, rate_card:, units: 1) }
  let!(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_datetime: Time.utc(2026, 1, 1),
      rate_model: "standard", rate_properties: {"amount" => "20"}, billing_interval_unit: "month", billing_interval_count: 1)
  end

  let!(:billing_cycle) do
    create(:billing_cycle, organization:, subscription:, subscription_product_item:,
      billing_at:, period_from: Time.utc(2026, 6, 1), period_to: Time.utc(2026, 6, 30).end_of_day)
  end

  it "creates a single invoice for the subscription" do
    expect { result }.to change(Invoice, :count).by(1)

    expect(result).to be_success
    expect(result.invoice.invoice_type).to eq("subscription")
    expect(result.invoice.subscriptions).to eq([subscription])
  end

  it "builds one fee per cycle with the computed amount" do
    result

    fees = result.invoice.fees
    expect(fees.count).to eq(1)
    expect(fees.first.amount_cents).to eq(2000)
    expect(fees.first.fee_type).to eq("product_item")
    expect(result.invoice.fees_amount_cents).to eq(2000)
  end

  it "marks the processed cycles as done" do
    result

    expect(billing_cycle.reload.status).to eq("done")
  end

  context "when there are no pending cycles" do
    before { billing_cycle.done! }

    it "does not create an invoice" do
      expect { result }.not_to change(Invoice, :count)
      expect(result.invoice).to be_nil
    end
  end
end
