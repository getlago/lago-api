# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::CreateJob do
  let(:payment_request) { create(:payment_request) }

  let(:service_result) { PaymentRequests::Payments::CreateService::Result.new }
  let(:payment_provider) { "stripe" }

  before do
    allow(PaymentRequests::Payments::CreateService).to receive(:call!)
      .with(payable: payment_request, payment_provider:, payment_method_params: {})
      .and_return(service_result)
  end

  it "calls the stripe create service" do
    described_class.perform_now(payable: payment_request, payment_provider:, payment_method_params: {})

    expect(PaymentRequests::Payments::CreateService).to have_received(:call!)
  end

  context "when the provider raises a connection error" do
    let(:error) { Invoices::Payments::ConnectionError.new(StandardError.new("Connection failed")) }

    before { allow(PaymentRequests::Payments::CreateService).to receive(:call!).and_raise(error) }

    it "retries the job" do
      assert_performed_jobs(6, only: [described_class]) do
        expect do
          described_class.perform_later(payable: payment_request, payment_provider:, payment_method_params: {})
        end.to raise_error(Invoices::Payments::ConnectionError)
      end
    end
  end
end
