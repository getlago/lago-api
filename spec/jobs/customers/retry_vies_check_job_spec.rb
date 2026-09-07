# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RetryViesCheckJob do
  let(:customer) { create(:customer) }

  it "finds the customer by ID and runs the VIES check" do
    result = Customers::ViesCheckService::Result.new.service_failure!(code: "vies_error", message: "VIES check failed")
    allow(Customers::ViesCheckService).to receive(:call).and_return(result)

    described_class.perform_now(customer.id)

    expect(Customers::ViesCheckService).to have_received(:call).with(customer:)
  end
end
