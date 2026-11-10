# frozen_string_literal: true

require "rails_helper"

describe "Daily Usage when a subscription terminates mid-period", :premium, cache: :redis do
  let(:organization) do
    create(:organization, webhook_url: nil, email_settings: [], premium_integrations: %w[revenue_analytics])
  end
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "items", field_name: "quantity") }
  let(:plan) { create(:plan, organization:, amount_cents: 0, pay_in_advance: false) }
  let(:upgraded_plan) { create(:plan, organization:, amount_cents: 1_000, pay_in_advance: false) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }
  let(:external_subscription_id) { "subscription_daily_usage" }

  before { charge }

  def send_usage(day, quantity)
    travel_to(DateTime.new(2025, 11, day, 12)) do
      create_event({
        code: billable_metric.code,
        external_subscription_id:,
        properties: {quantity:}
      })
    end
  end

  def compute_daily_usage(day)
    travel_to(DateTime.new(2025, 11, day + 1, 0, 10)) { perform_usage_update }
  end

  it "reports only the termination day's usage" do
    travel_to(DateTime.new(2025, 11, 1)) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: external_subscription_id,
        plan_code: plan.code,
        billing_time: "calendar"
      })
    end

    subscription = customer.subscriptions.sole

    send_usage(1, 1)
    compute_daily_usage(1)
    send_usage(2, 2)
    compute_daily_usage(2)
    send_usage(3, 3)

    travel_to(DateTime.new(2025, 11, 3, 18)) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: external_subscription_id,
        plan_code: upgraded_plan.code,
        billing_time: "calendar"
      })
    end

    expect(subscription.reload).to be_terminated

    daily_usages = subscription.daily_usages.order(:usage_date)
    termination_day = daily_usages.last

    expect(daily_usages.pluck(:usage_date)).to eq([
      Date.new(2025, 11, 1),
      Date.new(2025, 11, 2),
      Date.new(2025, 11, 3)
    ])
    expect(termination_day.usage["amount_cents"]).to eq((1 + 2 + 3) * 100)
    expect(termination_day.usage_diff["amount_cents"]).to eq(3 * 100)
    expect(daily_usages.sum { |daily_usage| daily_usage.usage_diff["amount_cents"] }).to eq(termination_day.usage["amount_cents"])
  end
end
