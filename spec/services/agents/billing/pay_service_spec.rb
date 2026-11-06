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

    it "returns the limit error without creating a top-up" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(paid_credits: ["amount_below_minimum"])
      expect(registration.wallet.wallet_transactions).to be_empty
    end
  end

  context "when the input is invalid" do
    let(:params) { {amount_cents: "1.5", shared_payment_token: ""} }

    it "returns the errors" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(amount_cents: ["value_is_invalid"], shared_payment_token: ["value_is_mandatory"])
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

    it "creates no top-up and lets the same request be retried" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(payment_method: ["stripe_customer_not_created"])
      expect(registration.wallet.wallet_transactions).to be_empty

      allow(::Stripe::Customer).to receive(:create).and_return(::Stripe::Customer.construct_from(id: "cus_agent"))

      retried = described_class.call(storefront:, registration:, params:)
      expect(retried).to be_success
      expect(customer.stripe_customer.provider_customer_id).to eq("cus_agent")
    end
  end
end
