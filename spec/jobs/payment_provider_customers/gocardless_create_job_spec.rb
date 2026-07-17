# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::GocardlessCreateJob do
  let(:gocardless_customer) { create(:gocardless_customer) }

  it "calls the gocardless create service" do
    allow(PaymentProviderCustomers::GocardlessService).to receive(:call!)
      .and_return(BaseService::Result.new)

    described_class.perform_now(gocardless_customer)

    expect(PaymentProviderCustomers::GocardlessService).to have_received(:call!).with(:create, gocardless_customer)
  end
end
