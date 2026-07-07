# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RetryViesCheckJob do
  let(:customer) { create(:customer) }

  it "finds the customer by ID and delegates to ViesCheckJob" do
    allow(Customers::ViesCheckService).to receive(:call).and_call_original

    described_class.perform_now(customer.id)

    expect(Customers::ViesCheckService).to have_received(:call).with(customer:)
  end
end
