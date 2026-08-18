# frozen_string_literal: true

require "rails_helper"

describe "Lifetime usage with pay in advance invoiceable charges", :premium, :time_travel do
  let(:organization) do
    create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["lifetime_usage", "progressive_billing"])
  end
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:charge) do
    create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: true, properties: {amount: "10"})
  end

  before { charge }

  def subscribe
    create_subscription(
      {
        external_customer_id: customer.external_id,
        external_id: customer.external_id,
        plan_code: plan.code
      }
    )
    customer.subscriptions.sole
  end

  # The immediate pay-in-advance invoice lands inside the still-open period, so its usage is on the
  # invoiced side while the current usage still reports it. Whether it shows up doubled depends on
  # when the invoiced counter was last refreshed, hence the two orderings below.
  it "counts the open period usage once when the event lands before any lifetime usage refresh" do
    subscription = subscribe

    ingest_event(subscription, billable_metric, 1)

    expect(Invoice.sole.fees.charge.sum(:amount_cents)).to eq(1000)

    lifetime_usage = subscription.lifetime_usage.reload
    expect(lifetime_usage.invoiced_usage_amount_cents).to eq(1000)
    expect(lifetime_usage.current_usage_amount_cents).to be_zero
    expect(lifetime_usage.total_amount_cents).to eq(1000)
  end

  it "counts the open period usage once when the event lands after a lifetime usage refresh" do
    subscription = subscribe

    pass_time 1.day

    ingest_event(subscription, billable_metric, 1)

    lifetime_usage = subscription.lifetime_usage.reload
    expect(lifetime_usage.invoiced_usage_amount_cents).to eq(1000)
    expect(lifetime_usage.current_usage_amount_cents).to be_zero
    expect(lifetime_usage.total_amount_cents).to eq(1000)
  end

  it "keeps counting the usage once after the period rolls over" do
    subscription = subscribe

    ingest_event(subscription, billable_metric, 1)

    pass_time 1.month

    lifetime_usage = subscription.lifetime_usage.reload
    expect(lifetime_usage.invoiced_usage_amount_cents).to eq(1000)
    expect(lifetime_usage.current_usage_amount_cents).to be_zero
    expect(lifetime_usage.total_amount_cents).to eq(1000)
  end

  context "with a usage threshold above the pay in advance amount" do
    let(:usage_threshold) { create(:usage_threshold, plan:, amount_cents: 1500) }

    before { usage_threshold }

    it "does not issue a progressive billing invoice when the event lands before any refresh" do
      subscription = subscribe

      ingest_event(subscription, billable_metric, 1)

      expect(subscription.lifetime_usage.reload.total_amount_cents).to eq(1000)
      expect(Invoice.progressive_billing.count).to be_zero
    end

    it "does not issue a progressive billing invoice when the event lands after a refresh" do
      subscription = subscribe

      pass_time 1.day

      ingest_event(subscription, billable_metric, 1)

      expect(subscription.lifetime_usage.reload.total_amount_cents).to eq(1000)
      expect(Invoice.progressive_billing.count).to be_zero
    end
  end
end
