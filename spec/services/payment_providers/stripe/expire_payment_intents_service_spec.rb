# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::ExpirePaymentIntentsService do
  subject(:result) { described_class.call(payment_provider) }

  let(:payment_provider) { create(:stripe_provider) }
  let(:organization) { payment_provider.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:payment_intent) { create(:payment_intent, invoice:) }

  before do
    create(:stripe_customer, customer:, payment_provider:)
    payment_intent
  end

  it "expires active payment intents of the provider's invoices" do
    expect { result }.to change { payment_intent.reload.status }.from("active").to("expired")
  end

  it "is successful" do
    expect(result).to be_success
  end

  context "when the payment intent belongs to another provider's customer" do
    let(:other_provider) { create(:stripe_provider, organization:) }
    let(:other_customer) { create(:customer, organization:) }
    let(:other_invoice) { create(:invoice, customer: other_customer, organization:) }
    let(:other_payment_intent) { create(:payment_intent, invoice: other_invoice) }

    before do
      create(:stripe_customer, customer: other_customer, payment_provider: other_provider)
      other_payment_intent
    end

    it "does not expire it" do
      expect { result }.not_to change { other_payment_intent.reload.status }
    end
  end
end
