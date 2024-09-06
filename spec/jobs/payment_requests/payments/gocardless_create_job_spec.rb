# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::GocardlessCreateJob, type: :job do
  let(:payment_request) { create(:payment_request) }

  let(:gocardless_service) { instance_double(PaymentRequests::Payments::GocardlessService) }
  let(:service_result) { BaseService::Result.new }

  before do
    allow(PaymentRequests::Payments::GocardlessService).to receive(:new)
      .with(payment_request)
      .and_return(gocardless_service)
    allow(gocardless_service).to receive(:create)
      .and_return(service_result)
  end

  it "calls the stripe create service" do
    described_class.perform_now(payment_request)

    expect(PaymentRequests::Payments::GocardlessService).to have_received(:new)
    expect(gocardless_service).to have_received(:create)
  end

  it "does not send a payment requested email" do
    expect { described_class.perform_now(payment_request) }
      .not_to have_enqueued_mail(PaymentRequestMailer, :requested)
  end

  context "when the payment fails" do
    let(:service_result) do
      BaseService::Result.new.tap do |result|
        result.payable = instance_double(PaymentRequest, payment_failed?: true)
      end
    end

    it "sends a payment requested email" do
      expect { described_class.perform_now(payment_request) }
        .to have_enqueued_mail(PaymentRequestMailer, :requested)
        .with(params: {payment_request:}, args: [])
    end
  end
end
