# frozen_string_literal: true

require "rails_helper"

describe "Subscriptions Termination Scenario", :scenarios, type: :request do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, name: "Premium Plan", code: "premium_plan", amount_cents: 49_00) }
  let(:customer) { create(:customer, external_id: "cust#{external_id}", organization:) }

  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "ops", field_name: "ops_count") }
  let(:charge) { create(:standard_charge, billable_metric:, plan:, amount_currency: "EUR", properties: {amount: "5"}) }

  let(:bm_2) { create(:sum_billable_metric, organization:, code: "api", field_name: "api_count") }
  let(:charge_2) { create(:standard_charge, billable_metric: bm_2, plan:, amount_currency: "EUR", properties: {amount: "100"}) }

  let(:external_id) { "alerting-v1" }
  let(:subscription_external_id) { "sub_#{external_id}" }

  let(:alert) do
    alert = UsageMonitoring::UsageAmountAlert.create!(organization:, subscription_external_id:, code: :simple)
    alert.thresholds.create!(value: 15_00, code: :warn, organization:)
    alert.thresholds.create!(value: 30_00, code: :warn, organization:)
    alert.thresholds.create!(value: 50_00, code: :alert, organization:)
    alert.reload
  end

  include_context "with webhook tracking"

  def send_event!(ops_count)
    create_event({
      code: billable_metric.code,
      transaction_id: "tr_#{SecureRandom.hex(16)}",
      external_subscription_id: subscription_external_id,
      properties: {"ops_count" => ops_count}
    })
  end

  before do
    charge
    charge_2
  end

  it "works" do
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: subscription_external_id,
      plan_code: plan.code
    })
    alert

    send_event! 20

    # result = ::Invoices::CustomerUsageService.call(customer:, subscription: customer.subscriptions.sole, apply_taxes: false, with_cache: false)
    # pp result.usage.to_h

    UsageMonitoring::ProcessActivityService.call(organization: organization, subscription_external_id:)
  end

  context "with deleted_at"
  it "maybe works" do
    alert = UsageMonitoring::UsageAmountAlert.create!(organization:, subscription_external_id:)
    expect(alert.deleted_at).to be_nil
    alert.discard!
    expect(alert.deleted_at).not_to be_nil
    alert.reload
    expect(alert.deleted_at).not_to be_nil

    new_alert = UsageMonitoring::UsageAmountAlert.create!(organization:, subscription_external_id:)
    pps new_alert
  end
end
