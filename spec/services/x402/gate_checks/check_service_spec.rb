# frozen_string_literal: true

require "rails_helper"

describe X402::GateChecks::CheckService, :premium, cache: :null do
  subject(:result) { described_class.call(organization:, params:) }

  include_context "with an x402 payment"

  let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:agent_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
  let(:customer) { create(:customer, organization:, x402_agent_address: agent_address) }
  let(:wallet) do
    create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, ongoing_balance_cents: 0,
      balance_cents: 1_500, credits_balance: 15, ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: 2)
  end
  let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{agent_address}_#{plan.code}") }
  let(:params) do
    {
      connection_code: connection.code, wallet_code: "agent_credits", agent_address:, resource: "POST /v1/generate",
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
      expect(result).to have_attributes(requirements: nil, external_subscription_id: subscription.external_id, balance_credits: 13)
    end

    it "makes no facilitator call" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end

    context "with the agent address claimed in lowercase" do
      let(:params) { super().merge(agent_address: agent_address.downcase) }

      it "passes with the checksummed external subscription id" do
        expect(result).to have_attributes(requirements: nil, external_subscription_id: subscription.external_id)
      end
    end

    context "with the agent address claimed in uppercase hex" do
      let(:params) { super().merge(agent_address: "0x#{agent_address.delete_prefix("0x").upcase}") }

      it "passes with the checksummed external subscription id" do
        expect(result).to have_attributes(requirements: nil, external_subscription_id: subscription.external_id)
      end
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
      expect(result).to have_attributes(requirements: [evm_requirement], external_subscription_id: nil, balance_credits: 0)
    end

    it "creates nothing" do
      expect { result }.not_to change { [Customer.count, Wallet.count, Subscription.count, X402::Settlement.count] }
    end

    context "when the connection refuses strangers" do
      let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

      it "refuses with buyer_not_recognized" do
        expect(result.error.messages).to eq(base: ["buyer_not_recognized"])
      end
    end
  end

  context "without an agent address" do
    let(:params) { super().except(:agent_address) }

    it "challenges as a stranger" do
      expect(result.requirements).to eq([evm_requirement])
    end

    context "when the connection refuses strangers" do
      let(:connection) { create(:x402_connection, organization:, auto_create_customers: false) }

      it "refuses with buyer_not_recognized" do
        expect(result.error.messages).to eq(base: ["buyer_not_recognized"])
      end
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
    "truncated hex" => "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dc",
    "hex without the 0x prefix" => "f4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
    "a wrong EIP-55 checksum" => "0xF4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
    "a CAIP-10 account id" => "eip155:8453:0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
    "an empty string" => ""
  }.each do |shape, address|
    context "with an agent address given as #{shape}" do
      let(:agent_address) { address }

      it "refuses the field as invalid_format" do
        expect(result.error.messages).to eq(agent_address: ["invalid_format"])
      end
    end
  end

  context "with an agent address longer than any address" do
    let(:agent_address) { "1" * 45 }

    before { allow(X402::Base58).to receive(:decode).and_call_original }

    it "refuses the field as invalid_format" do
      expect(result.error.messages).to eq(agent_address: ["invalid_format"])
    end

    it "never decodes it" do
      result
      expect(X402::Base58).not_to have_received(:decode).with("1" * 45)
    end
  end

  context "with a Solana transaction signature as the agent address" do
    let(:agent_address) { X402::Base58.encode(SecureRandom.random_bytes(64)) }

    it "refuses the field as invalid_format" do
      expect(result.error.messages).to eq(agent_address: ["invalid_format"])
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

      before { 2.times { described_class.call(organization:, params:) } }

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
    let(:agent_address) { "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG" }

    before do
      wallet
      subscription
    end

    it "passes with its external subscription id" do
      expect(result).to have_attributes(requirements: nil, external_subscription_id: "x402_#{agent_address}_#{plan.code}")
    end

    it "makes no facilitator call" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end
  end

  context "without an agent address on a Solana-only connection" do
    let(:connection) { create(:x402_connection, :solana, organization:, cdp_api_key_id:, cdp_api_key_secret:) }
    let(:params) { super().except(:agent_address) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: cdp_fixture("supported")) }

    it "challenges with the Solana entry" do
      expect(result.requirements.map { |entry| entry[:network] }).to eq(["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"])
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

    context "when /supported is unavailable" do
      before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 503, body: "{}") }

      it "fails as a third-party error" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end
  end
end
