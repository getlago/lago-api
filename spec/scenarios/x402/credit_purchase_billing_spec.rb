# frozen_string_literal: true

require "rails_helper"

describe "x402 credit purchase billing", :premium do
  include_context "with an x402 payment"

  context "with the merchant clock 200 ms behind" do
    let(:organization) { create(:organization, webhook_url: nil, feature_flags: ["x402_payments"]) }
    let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
    let(:x402_evm_requirements) { super().merge("amount" => "10000000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10000000"}}) }
    let(:params) do
      {
        connection_code: x402_connection.code, plan_code: "agent_api", wallet_code: "agent_credits",
        payment: x402_evm_payment, payment_requirements: x402_evm_requirements,
        wallet: {name: "Agent credits", rate_amount: "0.001", currency: "USD"}
      }
    end

    before do
      travel_to(Time.zone.at(1_789_649_271, 123_456, :usec), with_usec: true)
      stub_cdp_facilitator
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "0.01"})
    end

    it "bills the paid call stamped at the subscription start" do
      settlement = api_call { post_with_token(organization, "/api/v1/x402/credit_purchases", {credit_purchase: params}) }[:x402_settlement]
      served_at = (Time.current - 0.2.seconds).floor(3)
      started_at = settlement[:subscription_started_at]&.then { Time.iso8601(it) }

      create_event({
        code: billable_metric.code,
        external_subscription_id: settlement[:external_subscription_id],
        timestamp: [served_at, started_at].compact.max.to_f,
        properties: {value: "1"}
      })

      usage = fetch_current_usage(customer: Customer.find(settlement[:lago_customer_id]))
      expect(usage[:customer_usage][:charges_usage].sole[:units]).to eq("1.0")
    end
  end
end
