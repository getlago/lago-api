# frozen_string_literal: true

require "rails_helper"

describe "Daily Usages: Fill History", :time_travel, :scenarios, type: :request, transaction: false do
  around { |test| lago_premium!(&test) }

  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: true) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, properties: {amount: "1"}) }
  let(:subscription) { customer.subscriptions.first }

  before { charge }

  it "fills daily usage history" do
    mar_18 = DateTime.new(2025, 3, 18, 11)
    mar_19 = DateTime.new(2025, 3, 19, 11)

    apr_16 = DateTime.new(2025, 4, 16, 11)
    apr_17 = DateTime.new(2025, 4, 17, 11)
    apr_18 = DateTime.new(2025, 4, 18, 11)
    apr_19 = DateTime.new(2025, 4, 19, 11)
    apr_20 = DateTime.new(2025, 4, 20, 11)
    may_18 = DateTime.new(2025, 5, 18, 11)

    travel_to(mar_18) do
      create_subscription(
        external_customer_id: customer.external_id,
        external_id: customer.external_id,
        plan_code: plan.code,
        billing_time: "anniversary"
      )
    end

    (mar_18..apr_18).each do |date|
      travel_to(date + 1.minute) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {"item_id" => 1}
          }
        )
      end
    end

    travel_back

    DailyUsages::FillHistoryService.call!(subscription:, from_date: mar_18.to_date, to_date: apr_20.to_date)

    expect(DailyUsage.count).to eq(34) # 34 days from mar_18 to apr_20

    first_daily_usage = DailyUsage.find_by(usage_date: mar_18.to_date)
    second_daily_usage = DailyUsage.find_by(usage_date: mar_19.to_date)

    second_last_daily_usage = DailyUsage.find_by(usage_date: apr_16.to_date)
    last_daily_usage = DailyUsage.find_by(usage_date: apr_17.to_date)

    first_next_period_daily_usage = DailyUsage.find_by(usage_date: apr_18.to_date)
    second_next_period_daily_usage = DailyUsage.find_by(usage_date: apr_19.to_date)

    expect(first_daily_usage).to have_attributes(
      usage_date: mar_18.to_date,
      from_datetime: mar_18,
      to_datetime: apr_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 100)),
      usage_diff: {}
    )

    expect(second_daily_usage).to have_attributes(
      usage_date: mar_19.to_date,
      from_datetime: mar_18,
      to_datetime: apr_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 200)),
      usage_diff: match(including("amount_cents" => 100))
    )

    expect(second_last_daily_usage).to have_attributes(
      usage_date: apr_16.to_date,
      from_datetime: mar_18,
      to_datetime: apr_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 3000)),
      usage_diff: match(including("amount_cents" => 100))
    )

    expect(last_daily_usage).to have_attributes(
      usage_date: apr_17.to_date,
      from_datetime: mar_18,
      to_datetime: apr_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 3100)),
      usage_diff: match(including("amount_cents" => 100))
    )

    expect(first_next_period_daily_usage).to have_attributes(
      usage_date: apr_18.to_date,
      from_datetime: apr_18.beginning_of_day,
      to_datetime: may_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 100)),
      usage_diff: match(including("amount_cents" => 100))
    )

    expect(second_next_period_daily_usage).to have_attributes(
      usage_date: apr_19.to_date,
      from_datetime: apr_18.beginning_of_day,
      to_datetime: may_18.beginning_of_day - 1.second,
      usage: match(including("amount_cents" => 100)),
      usage_diff: match(including("amount_cents" => 0))
    )
  end
end
