# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::GocardlessCheckoutUrlJob do
  subject(:gocardless_checkout_job) { described_class }

  let(:gocardless_customer) { create(:gocardless_customer) }

  it "calls generate_checkout_url method" do
    allow(PaymentProviderCustomers::GocardlessService).to receive(:call!)
      .and_return(BaseService::Result.new)

    gocardless_checkout_job.perform_now(gocardless_customer)

    expect(PaymentProviderCustomers::GocardlessService).to have_received(:call!).with(:generate_checkout_url, gocardless_customer)
  end
end
