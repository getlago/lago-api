# frozen_string_literal: true

require "rails_helper"

describe "Daily Usages: a filter getting its first event mid-period", :premium do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "characters", field_name: "count") }
  let(:subscription) { organization.subscriptions.sole }

  before do
    create(:billable_metric_filter, billable_metric:, key: "model", values: %w[a b c])

    travel_to(DateTime.new(2025, 3, 1, 1)) do
      create_plan({
        name: "Startup",
        code: "startup",
        interval: "monthly",
        amount_cents: 0,
        amount_currency: "EUR",
        pay_in_advance: false,
        charges: [{
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          pay_in_advance: false,
          properties: {amount: "2"},
          filters: [
            {invoice_display_name: "A", properties: {amount: "1"}, values: {model: %w[a]}},
            {invoice_display_name: "B", properties: {amount: "3"}, values: {model: %w[b]}}
          ]
        }]
      })

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_startup",
        plan_code: "startup",
        billing_time: "calendar"
      })
    end

    # c falls in the default bucket on day 2, b gets its first event on day 3
    {2 => {"a" => 10, "c" => 5}, 3 => {"b" => 1}}.each do |day, counts|
      travel_to(DateTime.new(2025, 3, day, 12)) do
        counts.each do |model, count|
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {model:, count:}
          })
        end
      end

      travel_to(DateTime.new(2025, 3, day + 1, 0, 10)) { perform_usage_update }
    end
  end

  it "gives the filter its first event only" do
    usage_diff = subscription.daily_usages.find_by!(usage_date: Date.new(2025, 3, 3)).usage_diff
    filter_diffs = usage_diff["charges_usage"].sole["filters"].to_h do |f|
      [f["values"], [f["amount_cents"], BigDecimal(f["units"]).to_s("F"), f["events_count"]]]
    end

    expect(filter_diffs).to eq({"model" => %w[a]} => [0, "0.0", 0], {"model" => %w[b]} => [300, "1.0", 1], nil => [0, "0.0", 0])
  end

  it "does not flag the day for recompute" do
    expect(DailyUsages::RecomputeDiffsService.call!(subscription:, from_date: Date.new(2025, 3, 1), dry_run: true).daily_usages).to be_empty
  end
end
