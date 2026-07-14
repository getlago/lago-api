# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::StripeCreateJob do
  let(:stripe_customer) { create(:stripe_customer) }

  it "calls the stripe create service" do
    allow(PaymentProviderCustomers::StripeService).to receive(:call!)
      .and_return(BaseService::Result.new)

    described_class.perform_now(stripe_customer)

    expect(PaymentProviderCustomers::StripeService).to have_received(:call!).with(:create, stripe_customer)
  end
end
