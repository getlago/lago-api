# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::ExpirePaymentIntentsJob do
  it "calls the expire payment intents service" do
    allow(PaymentProviders::Stripe::ExpirePaymentIntentsService).to receive(:call!)

    provider = instance_double(PaymentProviders::StripeProvider)
    described_class.perform_now(provider)

    expect(PaymentProviders::Stripe::ExpirePaymentIntentsService).to have_received(:call!).with(provider)
  end
end
