# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::PaystackCreateJob do
  let(:paystack_customer) { create(:paystack_customer) }

  it "calls the Paystack create service" do
    allow(PaymentProviderCustomers::PaystackService).to receive(:call!)
      .and_return(BaseService::Result.new)

    described_class.perform_now(paystack_customer)

    expect(PaymentProviderCustomers::PaystackService).to have_received(:call!).with(:create, paystack_customer)
  end
end
