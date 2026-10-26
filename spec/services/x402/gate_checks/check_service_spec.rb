# frozen_string_literal: true

require "rails_helper"

describe X402::GateChecks::CheckService, :premium, cache: :null do
  subject(:result) { described_class.call(organization:, params:) }

  include_context "with an x402 payment"
  include SignInWithXSigner

  let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:agent_key) { siwx_evm_key }
  let(:agent_address) { siwx_address(agent_key) }
  let(:siwx) { signed_siwx(agent_key) }
  let(:customer) { create(:customer, organization:, x402_agent_address: agent_address) }
  let(:wallet) do
    create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, ongoing_balance_cents: 0,
      balance_cents: 1_500, credits_balance: 15, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
  end
  let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }
  let(:params) do
    {
      connection_code: connection.code, wallet_code: "agent_credits", siwx:, resource: "POST /v1/generate",
      plan_code: plan.code, billable_metric_code: billable_metric.code, amount_cents: 1_000, estimated_call_cost_cents: 1
    }
  end
  let(:evm_requirement) do
    {
      scheme: "exact", network: "eip155:84532", asset: "usdc", asset_address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      extra: {"name" => "USDC", "version" => "2"}, pay_to: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
      amount_atomic: "10000000", max_timeout_seconds: 60
    }
  end

  before { create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true) }

  context "with a funded agent" do
    before do
      wallet
      subscription
    end

    it "passes on the computed base while the stored ongoing balance is stale" do
      expect(result).to have_attributes(
        requirements: nil, sign_in_chains: nil, external_subscription_id: subscription.external_id, balance_credits: 13
      )
    end

    it "records the nonce" do
      result
      expect(X402::SignInNonce.sole).to have_attributes(organization:, agent_address:, nonce: siwx["nonce"])
    end

    it "makes no facilitator call" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end

    context "with a wallet restricted to other fee types" do
      let(:wallet) do
        create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, allowed_fee_types: ["subscription"],
          balance_cents: 1_500, credits_balance: 15)
      end

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end

    context "with a pending subscription beside the active one" do
      before { create(:subscription, :pending, customer:, plan:, external_id: subscription.external_id) }

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end

    context "with a replayed proof" do
      before { described_class.call(organization:, params:) }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end

      it "keeps one nonce" do
        result
        expect(X402::SignInNonce.count).to eq(1)
      end
    end

    context "with the agent's address in lowercase" do
      let(:siwx) { signed_siwx(agent_key, address: agent_address.downcase) }

      it "passes" do
        expect(result.requirements).to be_nil
      end

      it "records the nonce under the EIP-55 address" do
        result
        expect(X402::SignInNonce.sole).to have_attributes(agent_address:)
      end
    end

    context "with a passed proof re-sent with its address in lowercase" do
      subject(:result) { described_class.call(organization:, params: params.merge(siwx: siwx.merge("address" => agent_address.downcase))) }

      before { described_class.call(organization:, params:) }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end

      it "keeps one nonce" do
        result
        expect(X402::SignInNonce.count).to eq(1)
      end
    end

    context "with a replayed proof whose agent can no longer cover a call" do
      let(:params) { super().merge(estimated_call_cost_cents: 2) }

      before { described_class.call(organization:, params: params.merge(estimated_call_cost_cents: 1)) }

      it "refuses with nonce_already_used instead of challenging" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end
    end

    context "with the proof already used on another connection of the organization" do
      let(:other_connection) { create(:x402_connection, organization:) }

      before { described_class.call(organization:, params: params.merge(connection_code: other_connection.code)) }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end
    end

    context "with the same nonce recorded for another address" do
      before { create(:x402_sign_in_nonce, organization:, nonce: siwx["nonce"]) }

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end

    context "with the same nonce recorded in another organization" do
      before { create(:x402_sign_in_nonce, agent_address:, nonce: siwx["nonce"]) }

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end

    context "with a proof that got a challenge first" do
      let(:first_result) { described_class.call(organization:, params: params.merge(wallet_code: "other_wallet")) }

      before { first_result }

      it "challenged the first call" do
        expect(first_result.requirements).to eq([evm_requirement])
      end

      it "passes on the proof the challenge left unrecorded" do
        expect { result }.to change(X402::SignInNonce, :count).from(0).to(1)
        expect(result.requirements).to be_nil
      end
    end

    context "when the insert hits an unknown unique index" do
      before do
        allow(organization.x402_sign_in_nonces).to receive(:create!)
          .and_raise(ActiveRecord::RecordNotUnique.new('duplicate key value violates unique constraint "some_other_index"'))
      end

      it "re-raises" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  context "with a proof 6 minutes old", cache: :redis do
    let(:siwx) { signed_siwx(agent_key, issuedAt: 6.minutes.ago.utc.iso8601(3)) }
    let(:key) { "x402:reserved:#{wallet.id}" }

    before do
      wallet
      subscription
    end

    it "refuses with issued_at_too_old" do
      expect(result.error.messages).to eq(siwx: ["issued_at_too_old"])
    end

    it "records no nonce" do
      expect { result }.not_to change(X402::SignInNonce, :count)
    end

    it "leaves the reservation counter untouched" do
      result
      expect(Rails.cache.redis.then { it.exists?(key) }).to be(false)
    end
  end

  context "with a connection saved without allowed origins" do
    let(:connection) { create(:x402_connection, :without_allowed_origins, organization:) }

    before do
      wallet
      subscription
    end

    it "refuses with allowed_origins_not_configured" do
      expect(result.error.messages).to eq(base: ["allowed_origins_not_configured"])
    end

    it "records no nonce" do
      expect { result }.not_to change(X402::SignInNonce, :count)
    end

    context "without siwx" do
      let(:params) { super().except(:siwx) }

      it "challenges" do
        expect(result.requirements).to eq([evm_requirement])
      end
    end
  end

  context "with a lost insert race" do
    before do
      wallet
      subscription
      create(:x402_sign_in_nonce, organization:, agent_address:, nonce: siwx["nonce"])
      allow(organization.x402_sign_in_nonces).to receive(:exists?).and_return(false)
      allow(Sentry).to receive(:capture_exception)
    end

    context "with the reservation counter", cache: :redis do
      let(:key) { "x402:reserved:#{wallet.id}" }

      before { Rails.cache.redis.then { it.set(key, 5, ex: 60) } }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end

      it "restores the held reservation" do
        result
        expect(Rails.cache.read(key, raw: true)).to eq("5")
      end
    end

    context "when Redis is unreachable", cache: :redis do
      before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:1")) }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end
    end

    context "when the counter is switched off", cache: :redis do
      let(:organization) do
        create(:organization, premium_integrations: ["events_targeting_wallets"], feature_flags: ["x402_reservation_counter_disabled"])
      end
      let(:key) { "x402:reserved:#{wallet.id}" }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end

      it "leaves the counter untouched" do
        result
        expect(Rails.cache.redis.then { it.exists?(key) }).to be(false)
      end
    end
  end

  context "when the nonce insert fails", cache: :redis do
    let(:key) { "x402:reserved:#{wallet.id}" }

    before do
      wallet
      subscription
      Rails.cache.redis.then { it.set(key, 5, ex: 60) }
      allow(organization.x402_sign_in_nonces).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)
    end

    it "re-raises after restoring the held reservation" do
      expect { result }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Rails.cache.read(key, raw: true)).to eq("5")
    end
  end

  context "when the computed base is below the floor" do
    let(:wallet) do
      create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true,
        balance_cents: 1_100, credits_balance: 11, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
    end

    before do
      wallet
      subscription
    end

    it "challenges for the route's top-up" do
      expect(result).to have_attributes(requirements: [evm_requirement], external_subscription_id: subscription.external_id, balance_credits: 9)
    end

    it "records no nonce" do
      expect { result }.not_to change(X402::SignInNonce, :count)
    end
  end

  context "when the computed base equals the floor" do
    let(:wallet) do
      create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true,
        balance_cents: 1_200, credits_balance: 12, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
    end

    before do
      wallet
      subscription
    end

    it "passes" do
      expect(result.requirements).to be_nil
    end
  end

  context "with a larger per-call estimate" do
    let(:params) { super().merge(estimated_call_cost_cents: 2) }

    before do
      wallet
      subscription
    end

    it "scales the floor with the estimate" do
      expect(result.requirements).to eq([evm_requirement])
    end
  end

  context "with a wallet whose rate changed" do
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, rate_amount: 2.5) }

    before do
      wallet
      subscription
    end

    it "challenges for the same amount" do
      expect(result.requirements).to eq([evm_requirement])
    end
  end

  context "with a stranger" do
    it "challenges at a zero balance" do
      expect(result).to have_attributes(
        requirements: [evm_requirement], external_subscription_id: nil, balance_credits: 0,
        sign_in_chains: ["eip155:84532"]
      )
    end

    it "creates nothing" do
      expect { result }.not_to change { [Customer.count, Wallet.count, Subscription.count, X402::Settlement.count, X402::SignInNonce.count] }
    end

    context "when the connection refuses strangers" do
      let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

      it "refuses with buyer_not_recognized" do
        expect(result.error.messages).to eq(base: ["buyer_not_recognized"])
      end
    end
  end

  context "without siwx" do
    let(:params) { super().except(:siwx) }

    before do
      wallet
      subscription
    end

    it "challenges the funded agent's address as a stranger" do
      expect(result).to have_attributes(
        requirements: [evm_requirement], balance_credits: 0, external_subscription_id: nil,
        sign_in_chains: ["eip155:84532"]
      )
    end

    it("records no nonce") { expect { result }.not_to change(X402::SignInNonce, :count) }

    context "when the connection refuses strangers" do
      let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

      it("still challenges") { expect(result.requirements).to eq([evm_requirement]) }
    end
  end

  context "with a null siwx" do
    let(:params) { super().merge(siwx: nil) }

    it("challenges") { expect(result.requirements).to eq([evm_requirement]) }
  end

  context "with an empty siwx" do
    let(:params) { super().merge(siwx: {}) }

    it { expect(result.error.messages).to eq(siwx: ["value_is_invalid"]) }
  end

  context "with a siwx that is not an object" do
    let(:params) { super().merge(siwx: "token", amount_cents: 0) }

    it "reports it among the input errors" do
      expect(result.error.messages).to eq(siwx: ["value_is_invalid"], amount_cents: ["invalid_value"])
    end
  end

  context "when the connection refuses strangers" do
    let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

    context "with a known agent" do
      before do
        wallet
        subscription
      end

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end
  end

  {
    plan_code: ["value_is_mandatory"],
    billable_metric_code: ["value_is_mandatory"],
    wallet_code: ["value_is_mandatory"],
    amount_cents: ["value_is_mandatory"],
    estimated_call_cost_cents: ["value_is_mandatory"]
  }.each do |field, codes|
    context "without #{field}" do
      let(:params) { super().except(field) }

      it "refuses the field" do
        expect(result.error.messages).to eq(field => codes)
      end
    end
  end

  [0, -1, 1.5, "abc"].each do |value|
    context "with an estimated call cost of #{value.inspect}" do
      let(:params) { super().merge(estimated_call_cost_cents: value) }

      it "refuses the field as invalid_value" do
        expect(result.error.messages).to eq(estimated_call_cost_cents: ["invalid_value"])
      end
    end
  end

  context "with an estimate beyond the cap" do
    let(:params) { super().merge(estimated_call_cost_cents: 2**53) }

    it "refuses the field as invalid_value" do
      expect(result.error.messages).to eq(estimated_call_cost_cents: ["invalid_value"])
    end
  end

  context "with the reservation counter", cache: :redis do
    let(:wallet) do
      create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true,
        balance_cents: 1_100, credits_balance: 11, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
    end
    let(:key) { "x402:reserved:#{wallet.id}" }

    before do
      wallet
      subscription
      allow(Sentry).to receive(:capture_exception)
    end

    it "passes below the floor and holds the reservation for an hour" do
      expect(result.requirements).to be_nil
      expect(Rails.cache.read(key, raw: true)).to eq("1")
      expect(Rails.cache.redis.then { it.ttl(key) }).to be_between(3_590, 3_600)
    end

    context "with reservations already held" do
      before { Rails.cache.redis.then { it.set(key, 898, ex: 60) } }

      it "passes and re-arms the expiry" do
        expect(result.requirements).to be_nil
        expect(Rails.cache.read(key, raw: true)).to eq("899")
        expect(Rails.cache.redis.then { it.ttl(key) }).to be > 3_500
      end
    end

    context "when one more call is not covered" do
      before { Rails.cache.redis.then { it.set(key, 899, ex: 60) } }

      it "challenges and undoes the reservation" do
        expect(result.requirements).to eq([evm_requirement])
        expect(Rails.cache.read(key, raw: true)).to eq("899")
      end
    end

    context "with the largest accepted estimate" do
      let(:params) { super().merge(estimated_call_cost_cents: 2**53 - 1) }

      before { Rails.cache.redis.then { it.set(key, 5, ex: 60) } }

      it "challenges and restores the held reservation" do
        expect(result.requirements).to eq([evm_requirement])
        expect(Rails.cache.read(key, raw: true)).to eq("5")
      end

      it "does not report to Sentry" do
        result

        expect(Sentry).not_to have_received(:capture_exception)
      end
    end

    context "with several calls in a row" do
      let(:params) { super().merge(estimated_call_cost_cents: 300) }

      before { 2.times { described_class.call(organization:, params: params.merge(siwx: signed_siwx(agent_key))) } }

      it "challenges the third and holds only the first two" do
        expect(result.requirements).to eq([evm_requirement])
        expect(Rails.cache.read(key, raw: true)).to eq("600")
      end
    end

    context "with a pending subscription" do
      let(:subscription) { create(:subscription, :pending, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }

      it "refuses without touching the counter" do
        expect(result.error.messages).to eq(base: ["subscription_not_active"])
        expect(Rails.cache.redis.then { it.exists?(key) }).to be(false)
      end
    end

    context "when Redis is unreachable" do
      before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:1")) }

      it "falls back to the floor" do
        expect(result.requirements).to eq([evm_requirement])
      end

      it "reports the connection error" do
        result
        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Redis::CannotConnectError), anything)
      end
    end

    context "without a Redis cache store", cache: :null do
      it "falls back to the floor" do
        expect(result.requirements).to eq([evm_requirement])
      end

      it "reports the unavailable store" do
        result
        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(X402::ReservationCounter::UnavailableError), anything)
      end
    end

    context "when the counter is switched off" do
      let(:organization) do
        create(:organization, premium_integrations: ["events_targeting_wallets"], feature_flags: ["x402_reservation_counter_disabled"])
      end

      before { allow(Rails.cache).to receive(:redis).and_call_original }

      it "applies the floor" do
        expect(result.requirements).to eq([evm_requirement])
      end

      it "never reaches for Redis" do
        result
        expect(Rails.cache).not_to have_received(:redis)
      end

      it "reports nothing" do
        result
        expect(Sentry).not_to have_received(:capture_exception)
      end
    end
  end

  context "with a zero top-up amount" do
    let(:params) { super().merge(amount_cents: 0) }

    it "refuses the field as invalid_value" do
      expect(result.error.messages).to eq(amount_cents: ["invalid_value"])
    end
  end

  context "with an unknown connection code" do
    let(:params) { super().merge(connection_code: "unknown") }

    it "fails with connection_not_found" do
      expect(result.error.error_code).to eq("connection_not_found")
    end
  end

  context "with a discarded connection" do
    let(:connection) { create(:x402_connection, :discarded, organization:) }

    it "fails with connection_not_found" do
      expect(result.error.error_code).to eq("connection_not_found")
    end
  end

  context "with a misconfigured route" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "EUR") }

    context "when the connection refuses strangers" do
      let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

      context "with a stranger" do
        it "answers the route code first" do
          expect(result.error.messages).to eq(base: ["plan_currency_not_supported"])
        end
      end
    end

    context "with a known agent whose wallet is not enabled for x402" do
      let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: false, balance_cents: 1_500) }

      before { wallet }

      it "answers the route code first" do
        expect(result.error.messages).to eq(base: ["plan_currency_not_supported"])
      end
    end
  end

  context "with a wallet not enabled for x402" do
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: false, balance_cents: 1_500) }

    before do
      wallet
      subscription
    end

    it "refuses with wallet_not_x402_enabled" do
      expect(result.error.messages).to eq(base: ["wallet_not_x402_enabled"])
    end
  end

  context "with a terminated wallet" do
    let(:wallet) { create(:wallet, :terminated, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, balance_cents: 100_000, credits_balance: 1_000) }

    before do
      wallet
      subscription
    end

    it "challenges at a zero balance" do
      expect(result).to have_attributes(requirements: [evm_requirement], balance_credits: 0)
    end
  end

  context "with another customer's funded wallet under the same code" do
    let(:other_address) { "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5" }
    let(:other_customer) { create(:customer, organization:, x402_agent_address: other_address) }

    before do
      subscription
      create(:wallet, customer: other_customer, code: "agent_credits", currency: "USD", x402_enabled: true, balance_cents: 100_000, credits_balance: 1_000)
      create(:subscription, customer: other_customer, plan:, external_id: "x402_#{other_address}_#{plan.code}")
    end

    it "reads only the agent's own wallet" do
      expect(result).to have_attributes(requirements: [evm_requirement], balance_credits: 0)
    end
  end

  context "with a customer carrying a tax error" do
    before do
      wallet
      subscription
      create(:error_detail, owner: customer, organization:, error_code: :tax_error)
    end

    it "refuses with customer_not_refreshable" do
      expect(result.error.messages).to eq(base: ["customer_not_refreshable"])
    end
  end

  context "without a subscription for the route's plan" do
    before { wallet }

    it "challenges without an external subscription id" do
      expect(result).to have_attributes(requirements: [evm_requirement], external_subscription_id: nil)
    end

    context "with a terminated subscription" do
      before { create(:subscription, :terminated, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }

      it "challenges" do
        expect(result.requirements).to eq([evm_requirement])
      end
    end
  end

  context "with a pending subscription" do
    let(:subscription) { create(:subscription, :pending, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }

    before do
      wallet
      subscription
    end

    it "refuses with subscription_not_active" do
      expect(result.error.messages).to eq(base: ["subscription_not_active"])
    end
  end

  context "with an incomplete subscription" do
    let(:subscription) { create(:subscription, :incomplete, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }

    before do
      wallet
      subscription
    end

    it "refuses with subscription_not_active" do
      expect(result.error.messages).to eq(base: ["subscription_not_active"])
    end
  end

  context "with a top-up above the wallet's maximum" do
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, paid_top_up_max_amount_cents: 500) }

    before do
      wallet
      subscription
    end

    it "refuses the amount as amount_above_maximum" do
      expect(result.error.messages).to eq(amount_cents: ["amount_above_maximum"])
    end

    context "with a funded wallet" do
      let(:wallet) do
        create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, paid_top_up_max_amount_cents: 500,
          balance_cents: 1_500, credits_balance: 15)
      end

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end
  end

  context "with a credit purchase pending for the agent" do
    before { create(:x402_settlement, :pending, x402_connection: connection, payer_address: agent_address.downcase) }

    it "refuses with credit_purchase_pending" do
      expect(result.error.messages).to eq(base: ["credit_purchase_pending"])
    end

    context "with a funded agent" do
      before do
        wallet
        subscription
      end

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end
  end

  context "with a credit purchase pending for the agent in another organization" do
    before { create(:x402_settlement, :pending, payer_address: agent_address) }

    it "challenges" do
      expect(result.requirements).to eq([evm_requirement])
    end
  end

  context "with an invoice payment pending from the agent" do
    before { create(:x402_settlement, :pending, :invoice_payment, x402_connection: connection, payer_address: agent_address) }

    it "challenges" do
      expect(result.requirements).to eq([evm_requirement])
    end
  end

  context "with an EVM agent on a Solana-only connection" do
    let(:connection) { create(:x402_connection, :solana, organization:) }

    it "refuses with agent_address_family_unsupported" do
      expect(result.error.messages).to eq(base: ["agent_address_family_unsupported"])
    end

    it "makes no facilitator call" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end

    context "with a funded agent" do
      before do
        wallet
        subscription
      end

      it "passes" do
        expect(result.requirements).to be_nil
      end
    end

    context "with an agent below the floor" do
      let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true) }

      before do
        wallet
        subscription
      end

      it "refuses with agent_address_family_unsupported" do
        expect(result.error.messages).to eq(base: ["agent_address_family_unsupported"])
      end
    end
  end

  context "with a funded Solana agent" do
    let(:connection) { create(:x402_connection, :solana, organization:) }
    let(:agent_key) { siwx_svm_key }

    before do
      wallet
      subscription
    end

    it "passes with its external subscription id" do
      expect(result).to have_attributes(requirements: nil, external_subscription_id: "x402_#{agent_address}_#{plan.code}")
    end

    it "records the nonce under its base58 address" do
      result
      expect(X402::SignInNonce.sole).to have_attributes(organization:, agent_address:, nonce: siwx["nonce"])
    end

    it "makes no facilitator call" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end

    context "with a replayed proof" do
      before { described_class.call(organization:, params:) }

      it "refuses with nonce_already_used" do
        expect(result.error.messages).to eq(siwx: ["nonce_already_used"])
      end
    end
  end

  context "with a mainnet connection" do
    let(:connection) { create(:x402_connection, organization:, networks: ["eip155:8453"]) }
    let(:siwx) { signed_siwx(agent_key, chainId: "eip155:8453") }

    context "with a funded agent" do
      before do
        wallet
        subscription
      end

      it "passes" do
        expect(result).to have_attributes(requirements: nil, sign_in_chains: nil)
      end
    end

    context "with a testnet proof" do
      let(:siwx) { signed_siwx(agent_key) }

      it "refuses with unsupported_chain" do
        expect(result.error.messages).to eq(siwx: ["unsupported_chain"])
      end
    end

    context "without siwx" do
      let(:params) { super().except(:siwx) }

      it "offers sign-in on the mainnet chain" do
        expect(result.sign_in_chains).to eq(["eip155:8453"])
      end
    end
  end

  context "without siwx on a Solana-only connection" do
    let(:connection) { create(:x402_connection, :solana, organization:, cdp_api_key_id:, cdp_api_key_secret:) }
    let(:params) { super().except(:siwx) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: cdp_fixture("supported")) }

    it "challenges with the Solana entry" do
      expect(result.requirements.map { |entry| entry[:network] }).to eq(["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"])
    end

    it "offers sign-in on Solana only" do
      expect(result.sign_in_chains).to eq(["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"])
    end
  end

  context "with a connection offering both families" do
    let(:connection) do
      create(:x402_connection, organization:, networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
        payout_addresses: {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"},
        cdp_api_key_id:, cdp_api_key_secret:)
    end

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: cdp_fixture("supported")) }

    it "challenges with one entry per configured network" do
      expect(result.requirements.map { |entry| entry[:network] }).to eq(["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"])
    end

    it "offers sign-in on both families" do
      expect(result.sign_in_chains).to eq(["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"])
    end

    context "when /supported is unavailable" do
      before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 503, body: "{}") }

      it "fails as a third-party error" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end
  end
end
