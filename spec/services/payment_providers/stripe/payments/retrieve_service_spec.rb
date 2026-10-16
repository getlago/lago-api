# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::RetrieveService do
  subject(:result) { described_class.call(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }

  let(:payment) do
    create(:payment, customer:, organization:, payment_provider: stripe_provider,
      provider_payment_id: "pi_123", status: "requires_action")
  end

  let(:intent) do
    Stripe::PaymentIntent.construct_from(
      id: "pi_123", status: "requires_action", payment_method: {id: "pm_123", type: "card"}
    )
  end

  before { allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent) }

  it "reads the intent with its payment method expanded" do
    result

    expect(Stripe::PaymentIntent).to have_received(:retrieve).with(
      {id: "pi_123", expand: ["payment_method"]},
      {api_key: stripe_provider.secret_key}
    )
  end

  it "returns what the provider currently reports" do
    expect(result.status).to eq("requires_action")
    expect(result.payment_method_type).to eq("card")
  end

  context "when the intent has no payment method" do
    let(:intent) { Stripe::PaymentIntent.construct_from(id: "pi_123", status: "requires_action", payment_method: nil) }

    it "returns the status without a method" do
      expect(result.status).to eq("requires_action")
      expect(result.payment_method_type).to be_nil
    end
  end

  context "when the provider fails the read" do
    before do
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_raise(Stripe::AuthenticationError.new("bad key"))
    end

    it "lets the caller decide what the failure means" do
      expect { result }.to raise_error(Stripe::AuthenticationError)
    end
  end
end
