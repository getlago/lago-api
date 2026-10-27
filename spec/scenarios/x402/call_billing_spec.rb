# frozen_string_literal: true

require "rails_helper"

describe "x402 call billing", :premium do
  include_context "with an x402 payment"
  include SignInWithXSigner

  context "with the merchant clock 200 ms behind" do
    let(:organization) do
      create(:organization, webhook_url: nil, feature_flags: ["x402_payments"], premium_integrations: ["events_targeting_wallets"])
    end
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
      create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true, properties: {amount: "0.01"})
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

    context "when the agent signs in right after its subscription opened" do
      let(:agent_key) { siwx_evm_key }
      let(:agent_address) { siwx_address(agent_key) }
      let(:customer) { create(:customer, organization:, currency: nil, external_id: "x402_#{agent_address}", x402_agent_address: agent_address) }
      let(:gate_check_params) do
        {
          connection_code: x402_connection.code, wallet_code: "agent_credits", plan_code: "agent_api",
          billable_metric_code: billable_metric.code, amount_cents: 1_000, estimated_call_cost_cents: 1, siwx: signed_siwx(agent_key)
        }
      end

      before do
        X402::Subscriptions::ResolveService.call!(customer:, plan_code: "agent_api", family: :evm)
        create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, balance_cents: 1_500, credits_balance: 15)
      end

      it "bills the call served from credits stamped at the subscription start" do
        gate_check = api_call { post_with_token(organization, "/api/v1/x402/gate_checks", {gate_check: gate_check_params}) }[:gate_check]
        served_at = (Time.current - 0.2.seconds).floor(3)
        started_at = gate_check[:subscription_started_at]&.then { Time.iso8601(it) }

        create_event({
          code: billable_metric.code,
          external_subscription_id: gate_check[:external_subscription_id],
          timestamp: [served_at, started_at].compact.max.to_f,
          properties: {value: "1"}
        })

        usage = fetch_current_usage(customer:)
        expect(usage[:customer_usage][:charges_usage].sole[:units]).to eq("1.0")
      end
    end
  end
end
