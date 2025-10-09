# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Gocardless::HandleEventService do
  subject(:event_service) { described_class.new(event_json:) }

  let(:event_json) do
    path = Rails.root.join("spec/fixtures/gocardless/events.json")
    JSON.parse(File.read(path))["events"].first.to_json
  end

  let(:payment_service) { instance_double(Invoices::Payments::GocardlessService) }
  let(:service_result) { BaseService::Result.new }

  describe "#call" do
    context "when succeeded payment event" do
      it "routes the event to an other service" do
        allow(Invoices::Payments::GocardlessService).to receive(:new)
          .and_return(payment_service)
        allow(payment_service).to receive(:update_payment_status)
          .and_return(service_result)

        event_service.call

        expect(Invoices::Payments::GocardlessService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when event metadata contains payable_type PaymentRequest" do
      let(:payment_service) { instance_double(PaymentRequests::Payments::GocardlessService) }
      let(:service_result) { BaseService::Result.new }

      let(:event_json) do
        path = Rails.root.join("spec/fixtures/gocardless/events_payment_request.json")
        JSON.parse(File.read(path))["events"].first.to_json
      end

      it "routes the event to an other service" do
        allow(PaymentRequests::Payments::GocardlessService).to receive(:new)
          .and_return(payment_service)
        allow(payment_service).to receive(:update_payment_status)
          .and_return(service_result)

        event_service.call

        expect(PaymentRequests::Payments::GocardlessService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when event metadata contains invalid payable_type" do
      let(:event_json) do
        path = Rails.root.join("spec/fixtures/gocardless/events_invalid_payable_type.json")
        JSON.parse(File.read(path))["events"].first.to_json
      end

      it "routes the event to an other service" do
        expect {
          event_service.call
        }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
      end
    end

    context "when succeeded refund event" do
      let(:refund_service) { instance_double(CreditNotes::Refunds::GocardlessService) }
      let(:event_json) do
        path = Rails.root.join("spec/fixtures/gocardless/events_refund.json")
        JSON.parse(File.read(path))["events"].first.to_json
      end

      it "routes the event to an other service" do
        allow(CreditNotes::Refunds::GocardlessService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)

        event_service.call

        expect(CreditNotes::Refunds::GocardlessService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end
  end
end
