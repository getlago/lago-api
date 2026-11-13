# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Billing::PayService, :premium do
  subject(:result) { described_class.call(storefront:, registration:, params:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:params) { {amount_cents: 500, shared_payment_token: "spt_agent_1"} }
  let(:customer) { organization.customers.sole }

  before do
    storefront.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}])
    Agents::Billing::EnrollService.call!(storefront:, registration:, plan_code: plan.code)
    storefront.stripe_provider.update!(seller_profile: "profile_test_123")
    allow(::Stripe::Customer).to receive(:create).and_return(::Stripe::Customer.construct_from(id: "cus_agent"))
  end

  it "creates the agent's token-only Stripe customer and a top-up paid with the token" do
    expect(result).to be_success
    expect(result.replayed).to be(false)

    expect(customer).to have_attributes(payment_provider: "stripe", payment_provider_code: storefront.payment_provider_code)
    expect(customer.stripe_customer).to have_attributes(
      provider_customer_id: "cus_agent", provider_payment_methods: ["shared_payment_token"], payment_provider: storefront.stripe_provider
    )
    expect(result.wallet_transaction).to have_attributes(
      wallet: registration.wallet, status: "pending", transaction_status: "purchased", amount: 5,
      invoice_requires_successful_payment: true
    )
    expect(result.wallet_transaction.payment_method).to have_attributes(provider_method_type: "shared_payment_token", provider_method_id: "spt_agent_1")
  end

  it "returns the same top-up when the same token is sent again" do
    first = described_class.call(storefront:, registration:, params:)

    expect(result).to be_success
    expect(result.replayed).to be(true)
    expect(result.wallet_transaction).to eq(first.wallet_transaction)
    expect(registration.wallet.wallet_transactions.count).to eq(1)
    expect(::Stripe::Customer).to have_received(:create).once
  end

  it "pays a second top-up with a second token on the same Stripe customer" do
    first = described_class.call(storefront:, registration:, params:)
    second = described_class.call(storefront:, registration:, params: {amount_cents: 700, shared_payment_token: "spt_agent_2"})

    expect(second).to be_success
    expect(second.wallet_transaction).not_to eq(first.wallet_transaction)
    expect(second.wallet_transaction.amount).to eq(7)
    expect(::Stripe::Customer).to have_received(:create).once
  end

  context "when the amount is outside the wallet's top-up limits" do
    let(:params) { {amount_cents: 100, shared_payment_token: "spt_agent_1"} }

    it "returns the limit error on the amount without creating a top-up" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(amount_cents: ["amount_below_minimum"])
      expect(registration.wallet.wallet_transactions).to be_empty
    end

    it "refuses before creating the Stripe customer" do
      expect(result).not_to be_success
      expect(::Stripe::Customer).not_to have_received(:create)
      expect(storefront.agents_with_stripe_customer?).to be(false)
    end
  end

  context "when the input is invalid" do
    let(:params) { {amount_cents: "1.5", shared_payment_token: ""} }

    it "returns the errors" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(amount_cents: ["value_is_invalid"], shared_payment_token: ["value_is_mandatory"])
    end
  end

  context "when the token is malformed" do
    let(:params) { {amount_cents: 500, shared_payment_token: "x"} }

    it "refuses before creating the Stripe customer" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(shared_payment_token: ["value_is_invalid"])
      expect(::Stripe::Customer).not_to have_received(:create)
      expect(storefront.agents_with_stripe_customer?).to be(false)
    end
  end

  context "when the token is a JSON number" do
    let(:params) { {amount_cents: 500, shared_payment_token: 123} }

    it "refuses it as malformed" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(shared_payment_token: ["value_is_invalid"])
      expect(::Stripe::Customer).not_to have_received(:create)
    end
  end

  context "when the same token comes back with another amount" do
    it "refuses it instead of answering with the first payment" do
      first = described_class.call(storefront:, registration:, params:)
      second = described_class.call(storefront:, registration:, params: {amount_cents: 900, shared_payment_token: "spt_agent_1"})

      expect(first).to be_success
      expect(second).not_to be_success
      expect(second.error.messages).to eq(shared_payment_token: ["value_already_exist"])
      expect(registration.wallet.wallet_transactions.count).to eq(1)
    end
  end

  context "when the seller profile is cleared after a payment" do
    it "still answers a replay with the payment" do
      first = described_class.call(storefront:, registration:, params:)
      storefront.stripe_provider.update!(seller_profile: nil)

      expect(result).to be_success
      expect(result.replayed).to be(true)
      expect(result.wallet_transaction).to eq(first.wallet_transaction)
    end
  end

  context "when the storefront's Stripe connection has no seller profile" do
    before { storefront.stripe_provider.update!(seller_profile: nil) }

    it "refuses before touching Stripe" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["payments_not_accepted"])
      expect(::Stripe::Customer).not_to have_received(:create)
      expect(registration.wallet.wallet_transactions).to be_empty
    end
  end

  context "when the registration is not enrolled" do
    subject(:result) { described_class.call(storefront:, registration: create(:agent_registration, storefront:), params:) }

    it "returns enrollment_required" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["enrollment_required"])
    end
  end

  context "when Stripe refuses to create the customer" do
    before { allow(::Stripe::Customer).to receive(:create).and_raise(::Stripe::InvalidRequestError.new("error", nil)) }

    it "creates no top-up" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(shared_payment_token: ["stripe_customer_not_created"])
      expect(registration.wallet.wallet_transactions).to be_empty
    end

    context "when Stripe accepts the same request again" do
      let(:refused) { described_class.call(storefront:, registration:, params:) }

      before do
        refused
        allow(::Stripe::Customer).to receive(:create).and_return(::Stripe::Customer.construct_from(id: "cus_agent"))
      end

      it "creates the customer and the top-up" do
        expect(refused).not_to be_success
        expect(result).to be_success
        expect(customer.stripe_customer.provider_customer_id).to eq("cus_agent")
      end
    end
  end

  context "when the same token is sent twice at once", transaction: false do
    it "pays once and answers the second request with the same top-up" do
      registration
      storefront.stripe_provider.update!(seller_profile: "profile_test_123")

      # The first request pauses before creating the top-up, so the second runs while the first
      # has not committed yet.
      first_call = Queue.new
      first_call << true
      paused = Queue.new
      resume = Queue.new
      allow(WalletTransactions::CreateFromParamsService).to receive(:call).and_wrap_original do |original, **args|
        if first_call.pop(timeout: 0)
          paused << true
          resume.pop
        end

        original.call(**args)
      end

      pay = lambda do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(storefront: storefront.class.find(storefront.id), registration: registration.class.find(registration.id), params:)
          end
        end
      end

      first = pay.call
      paused.pop
      second = pay.call
      sleep 0.5
      resume << true

      results = [first.value, second.value]

      expect(results).to all(be_success)
      expect(results.map(&:replayed)).to eq([false, true])
      expect(registration.wallet.wallet_transactions.count).to eq(1)
    end
  end
end
