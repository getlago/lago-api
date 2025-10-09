# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::CreateJob do
  let(:payment_request) { create(:payment_request) }

  let(:service_result) { BaseService::Result.new }
  let(:payment_provider) { "stripe" }

  before do
    allow(PaymentRequests::Payments::CreateService).to receive(:call!)
      .with(payable: payment_request, payment_provider:)
      .and_return(service_result)
  end

  it "calls the stripe create service" do
    described_class.perform_now(payable: payment_request, payment_provider:)

    expect(PaymentRequests::Payments::CreateService).to have_received(:call!)
  end
end
