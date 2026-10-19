# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::GateCheckService, :premium, cache: :redis do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront events_targeting_wallets]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "EUR") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true) }
  let(:scope) { storefront.scope }
  let(:token) do
    JWT.encode(
      {iss: storefront.agent_url, sub: registration.id, scope:, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i},
      RsaPrivateKey, "RS256", {typ: "at+jwt"}
    )
  end
  let(:params) do
    {storefront_code: storefront.code, token:, billable_metric_code: billable_metric.code, estimated_call_cost_cents: 1}
  end
  let(:enrollment) { Agents::Billing::EnrollService.call!(storefront:, registration:, plan_code: plan.code) }
  let(:wallet) { enrollment.wallet }
  let(:key) { "x402:reserved:#{wallet.id}" }
  let(:billing_instructions) { "#{storefront.agent_url}/BILLING.md" }

  before do
    charge
    storefront.update!(plans: [{plan_code: plan.code}])
    wallet.update!(balance_cents: 1_100, credits_balance: 11, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
    allow(Sentry).to receive(:capture_exception)
  end

  it "lets a funded agent through on a plan in euros and holds the estimate for an hour" do
    expect(result).to be_success
    expect(result).to have_attributes(
      allowed: true, reason: nil, external_subscription_id: "agent_#{registration.id}",
      wallet_code: "agent_credits", balance_credits: 9, billing_instructions: nil
    )
    expect(Rails.cache.read(key, raw: true)).to eq("1")
    expect(Rails.cache.redis.then { it.ttl(key) }).to be_between(3_590, 3_600)
  end

  context "with the estimate as a string of digits" do
    let(:params) { super().merge(estimated_call_cost_cents: "1") }

    it "lets the agent through" do
      expect(result.allowed).to be(true)
    end
  end

  context "with several calls in a row" do
    let(:params) { super().merge(estimated_call_cost_cents: 300) }

    before { 2.times { described_class.call(organization:, params:) } }

    it "refuses the third and holds only the first two" do
      expect(result).to have_attributes(
        allowed: false, reason: "insufficient_credits", external_subscription_id: "agent_#{registration.id}",
        wallet_code: "agent_credits", balance_credits: 9, billing_instructions:
      )
      expect(Rails.cache.read(key, raw: true)).to eq("600")
    end
  end

  context "with an empty wallet" do
    before { wallet.update!(balance_cents: 0, credits_balance: 0, ongoing_usage_balance_cents: 0, credits_ongoing_usage_balance: 0) }

    it "refuses for insufficient credits and holds nothing" do
      expect(result).to have_attributes(allowed: false, reason: "insufficient_credits", billing_instructions:)
      expect(Rails.cache.read(key, raw: true)).to eq("0")
    end
  end

  context "when the agent is not enrolled" do
    let(:wallet) { create(:wallet) }

    it "asks for an enrollment" do
      expect(result).to have_attributes(
        allowed: false, reason: "enrollment_required", external_subscription_id: nil,
        wallet_code: nil, balance_credits: nil, billing_instructions:
      )
      expect(Rails.cache.redis.then { it.exists?(key) }).to be(false)
    end
  end

  context "when the agent's subscription was terminated" do
    before { enrollment.subscription.update!(status: :terminated, terminated_at: Time.current) }

    it "asks for an enrollment" do
      expect(result).to have_attributes(allowed: false, reason: "enrollment_required")
    end
  end

  context "when the agent's wallet was terminated" do
    before { wallet.update!(status: :terminated, terminated_at: Time.current) }

    it "asks for an enrollment" do
      expect(result).to have_attributes(allowed: false, reason: "enrollment_required")
    end
  end

  context "with a billing token" do
    let(:scope) { Agents::Auth::ChallengeService::BILLING_SCOPE }

    it "refuses the token" do
      expect(result.error.messages).to eq(token: ["invalid_token"])
    end
  end

  context "with a token of another storefront" do
    let(:token) do
      other = create(:agent_storefront_integration, organization:, code: "other_api")
      JWT.encode(
        {iss: other.agent_url, sub: registration.id, scope: other.scope, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i},
        RsaPrivateKey, "RS256", {typ: "at+jwt"}
      )
    end

    it "refuses the token" do
      expect(result.error.messages).to eq(token: ["invalid_token"])
    end
  end

  context "when the registration is revoked" do
    before { registration.update!(status: :revoked, revoked_at: Time.current) }

    it "refuses the registration" do
      expect(result.error.messages).to eq(base: ["registration_inactive"])
    end
  end

  context "with an unknown storefront code" do
    let(:params) { super().merge(storefront_code: "unknown") }

    it "answers not found" do
      expect(result.error.error_code).to eq("agent_storefront_not_found")
    end
  end

  context "with the storefront code of another organization" do
    let(:params) { super().merge(storefront_code: create(:agent_storefront_integration, code: "foreign_api").code) }

    it "answers not found" do
      expect(result.error.error_code).to eq("agent_storefront_not_found")
    end
  end

  context "with an action the plan does not charge" do
    let(:params) { super().merge(billable_metric_code: create(:billable_metric, organization:).code) }

    it "answers not found" do
      expect(result.error.error_code).to eq("charge_not_found")
    end
  end

  context "when the charge cannot target a wallet" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: false) }

    it "refuses with charge_not_targeted" do
      expect(result.error.messages).to eq(base: ["charge_not_targeted"])
    end
  end

  context "without the events targeting integration" do
    before { organization.update!(premium_integrations: %w[agent_storefront]) }

    it "refuses with charge_not_targeted" do
      expect(result.error.messages).to eq(base: ["charge_not_targeted"])
    end
  end

  context "with a pay-in-advance charge that is not invoiceable" do
    let(:charge) { create(:standard_charge, :regroup_paid_fees, plan:, billable_metric:, accepts_target_wallet: true) }

    it "refuses with charge_not_invoiceable" do
      expect(result.error.messages).to eq(base: ["charge_not_invoiceable"])
    end
  end

  context "when the plan gained a subscription fee after the enrollment" do
    before do
      enrollment
      plan.update!(amount_cents: 1_000)
    end

    it "refuses with plan_not_usage_only" do
      expect(result.error.messages).to eq(base: ["plan_not_usage_only"])
    end
  end

  context "when the merchant overrode the plan of the agent's subscription" do
    let(:child_plan) { create(:plan, organization:, parent: plan, code: plan.code, amount_cents: 0, amount_currency: "EUR") }

    before do
      create(:standard_charge, plan: child_plan, billable_metric:, parent: charge, accepts_target_wallet: false)
      enrollment.subscription.update!(plan: child_plan)
    end

    it "checks the plan the agent is billed on" do
      expect(result.error.messages).to eq(base: ["charge_not_targeted"])
    end
  end

  context "when the customer has a tax error" do
    before { create(:error_detail, owner: wallet.customer, organization:, error_code: :tax_error) }

    it "refuses with customer_not_refreshable" do
      expect(result.error.messages).to eq(base: ["customer_not_refreshable"])
    end
  end

  context "without the mandatory fields" do
    let(:params) { {} }

    it "refuses each one" do
      expect(result.error.messages).to eq(
        storefront_code: ["value_is_mandatory"],
        token: ["value_is_mandatory"],
        billable_metric_code: ["value_is_mandatory"],
        estimated_call_cost_cents: ["value_is_mandatory"]
      )
    end
  end

  [0, -1, "1.5", "abc", 2**53].each do |estimate|
    context "with an estimate of #{estimate.inspect}" do
      let(:params) { super().merge(estimated_call_cost_cents: estimate) }

      it "refuses the estimate as invalid_value" do
        expect(result.error.messages).to eq(estimated_call_cost_cents: ["invalid_value"])
      end
    end
  end

  context "when Redis is unreachable" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:1")) }

    it "falls back to the floor of 1 000 calls" do
      expect(result).to have_attributes(allowed: false, reason: "insufficient_credits")
    end

    it "reports the connection error" do
      result
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Redis::CannotConnectError), anything)
    end
  end

  context "when the counter is switched off" do
    let(:organization) do
      create(:organization, premium_integrations: %w[agent_storefront events_targeting_wallets], feature_flags: ["x402_reservation_counter_disabled"])
    end

    let(:params) { super().merge(estimated_call_cost_cents: 100) }

    before do
      wallet.update!(balance_cents: 100_200, credits_balance: 1_002)
      allow(Rails.cache).to receive(:redis).and_call_original
    end

    it "lets the agent through at the floor of 1 000 calls without touching Redis" do
      expect(result.allowed).to be(true)
      expect(Rails.cache).not_to have_received(:redis)
    end

    context "with a balance below the floor" do
      let(:params) { super().merge(estimated_call_cost_cents: 101) }

      it "refuses for insufficient credits" do
        expect(result).to have_attributes(allowed: false, reason: "insufficient_credits")
      end
    end
  end
end
