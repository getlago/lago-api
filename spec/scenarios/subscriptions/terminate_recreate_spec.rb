# frozen_string_literal: true

require "rails_helper"

describe "Subscription terminate and recreate on the same external_id", :premium do
  let(:organization) do
    create(:organization, webhook_url: nil, premium_integrations: ["lifetime_usage", "progressive_billing"])
  end
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "item_count") }
  let(:plan) { create(:plan, organization:, interval: :yearly, pay_in_advance: false, amount_cents: 365_00) }

  let(:subscription_at) { DateTime.new(2025, 3, 15) }
  let(:events_date) { DateTime.new(2025, 6, 1) }
  let(:rotation_date) { DateTime.new(2026, 3, 13) }
  let(:anniversary_date) { DateTime.new(2026, 3, 15) }

  before { create(:standard_charge, billable_metric:, plan:, properties: {amount: "1"}) }

  def terminated_subscription
    customer.subscriptions.order(created_at: :asc).first
  end

  def recreated_subscription
    customer.subscriptions.order(created_at: :asc).last
  end

  def subscription_params
    {
      external_customer_id: customer.external_id,
      external_id: customer.external_id,
      plan_code: plan.code,
      billing_time: "anniversary",
      subscription_at: subscription_at.iso8601
    }
  end

  # 5 events * 10 item_count * 1 euro = 50 euro of usage in the first period
  def add_events_to_subscription
    travel_to(events_date) do
      5.times do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: customer.external_id,
            properties: {"item_count" => 10}
          }
        )
      end
    end
  end

  # Terminate and immediately recreate on the same external_id, replaying the original anchor.
  # This is how customers hand-roll an upgrade when they need the anniversary date preserved.
  def rotate_subscription
    travel_to(rotation_date) do
      terminate_subscription(terminated_subscription)
      create_subscription(subscription_params)
    end
  end

  def start_original_subscription
    travel_to(subscription_at) { create_subscription(subscription_params) }
    add_events_to_subscription
  end

  it "starts the recreated subscription at the termination, keeping the anniversary anchor" do
    start_original_subscription
    rotate_subscription

    expect(recreated_subscription.id).not_to eq(terminated_subscription.id)
    expect(recreated_subscription).to be_active
    expect(recreated_subscription.subscription_at).to eq(subscription_at)
    expect(recreated_subscription.started_at).to eq(terminated_subscription.reload.terminated_at)
  end

  it "does not bill the terminated period a second time" do
    start_original_subscription

    rotate_subscription

    terminating_invoice = terminated_subscription.invoices.order(:created_at).last
    expect(terminating_invoice.fees.charge.sum(:amount_cents)).to eq(50_00)

    travel_to(anniversary_date) { perform_billing }

    boundaries = recreated_subscription.invoice_subscriptions.order(:created_at).last
    expect(boundaries.from_datetime).to eq(rotation_date)
    expect(boundaries.charges_from_datetime).to eq(rotation_date)

    anniversary_invoice = recreated_subscription.invoices.order(:created_at).last
    expect(anniversary_invoice.fees.charge.sum(:amount_cents)).to eq(0)

    # The 50 euro of usage is invoiced exactly once across the whole external_id lineage
    all_charge_fees = customer.invoices.flat_map { |invoice| invoice.fees.charge }
    expect(all_charge_fees.sum(&:amount_cents)).to eq(50_00)
  end

  it "carries the invoiced lifetime usage across the rotation without double counting it" do
    start_original_subscription

    travel_to(rotation_date) do
      perform_usage_update

      expect(terminated_subscription.lifetime_usage.reload.current_usage_amount_cents).to eq(50_00)
    end

    rotate_subscription

    travel_to(rotation_date) { perform_usage_update }

    lifetime_usage = recreated_subscription.lifetime_usage.reload

    # A fresh record, but the amount is recomputed from every invoice sharing
    # external_id + subscription_at, so the terminated subscription is included.
    expect(lifetime_usage.id).not_to eq(terminated_subscription.lifetime_usage.id)
    expect(lifetime_usage.invoiced_usage_amount_cents).to eq(50_00)
    expect(lifetime_usage.current_usage_amount_cents).to eq(0)
    expect(lifetime_usage.total_amount_cents).to eq(50_00)
  end
end
