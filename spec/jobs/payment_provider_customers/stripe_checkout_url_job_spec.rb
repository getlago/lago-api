# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::StripeCheckoutUrlJob do
  subject(:stripe_checkout_job) { described_class }

  let(:stripe_customer) { create(:stripe_customer) }

  it "calls generate_checkout_url method" do
    allow(PaymentProviderCustomers::StripeService).to receive(:call!)
      .and_return(PaymentProviderCustomers::StripeService::RESULTS.fetch(:generate_checkout_url).new)

    stripe_checkout_job.perform_now(stripe_customer)

    expect(PaymentProviderCustomers::StripeService).to have_received(:call!).with(:generate_checkout_url, stripe_customer)
  end
end
