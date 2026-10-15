# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethods::CreateFromSharedPaymentTokenService do
  subject(:result) { described_class.call(customer:, params:) }

  let(:customer) { create(:customer, organization:, payment_provider: "stripe", payment_provider_code: "stripe_1") }
  let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_1") }
  let(:provider_customer_id) { "cus_1" }
  let(:provider_payment_methods) { %w[shared_payment_token] }
  let(:params) { {payment_method_type: "provider", shared_payment_token: "spt_abc_123"} }

  let_it_be(:organization) { create_default(:organization) }

  before do
    create(:stripe_customer, customer:, payment_provider: stripe_provider, provider_customer_id:, provider_payment_methods:)
  end

  it "creates a single-use payment method row holding the token" do
    expect(result).to be_success
    expect(result.payment_method).to have_attributes(
      customer:, payment_provider: stripe_provider, provider_method_type: "shared_payment_token",
      provider_method_id: "spt_abc_123", is_default: false
    )
    expect(result.params).to eq(payment_method_type: "provider", payment_method_id: result.payment_method.id)
  end

  context "without a token" do
    let(:params) { {payment_method_type: "provider", payment_method_id: "pm_row"} }

    it "returns the params untouched" do
      expect(result).to be_success
      expect(result.payment_method).to be_nil
      expect(result.params).to eq(params)
    end
  end

  context "with a token and a payment method id" do
    let(:params) { {payment_method_type: "provider", payment_method_id: "pm_row", shared_payment_token: "spt_abc_123"} }

    it "refuses" do
      expect(result).not_to be_success
      expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
    end
  end

  context "with a value that is not a shared payment token" do
    let(:params) { {shared_payment_token: "pm_123"} }

    it "refuses" do
      expect(result.error.messages[:payment_method]).to eq(["value_is_invalid"])
    end
  end

  context "when the Stripe connection also accepts cards" do
    let(:provider_payment_methods) { %w[card] }

    it "refuses" do
      expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
    end
  end

  context "when the Stripe customer is not created yet" do
    let(:provider_customer_id) { nil }

    it "refuses with a code the caller can retry on" do
      expect(result.error.messages[:payment_method]).to eq(["stripe_customer_not_created"])
    end
  end

  context "when the same token was already enrolled for the customer" do
    before { described_class.call(customer:, params:) }

    it "refuses" do
      expect(result.error.messages[:payment_method]).to eq(["value_already_exist"])
      expect(customer.payment_methods.count).to eq(1)
    end
  end
end
