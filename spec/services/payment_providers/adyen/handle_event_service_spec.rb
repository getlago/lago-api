# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Adyen::HandleEventService do
  subject(:event_service) { described_class.new(organization:, event_json:) }

  let(:organization) { create(:organization) }

  describe "#call" do
    let(:payment_service) { instance_double(Invoices::Payments::AdyenService) }
    let(:payment_provider_service) { instance_double(PaymentProviderCustomers::AdyenService) }
    let(:service_result) { BaseService::Result.new }

    before do
      allow(Invoices::Payments::AdyenService).to receive(:new)
        .and_return(payment_service)
      allow(PaymentProviderCustomers::AdyenService).to receive(:new)
        .and_return(payment_provider_service)
      allow(payment_service).to receive(:update_payment_status)
        .and_return(service_result)
      allow(payment_provider_service).to receive(:preauthorise)
        .and_return(service_result)
    end

    context "when succeeded authorisation event" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_response.json")
        File.read(path)
      end

      it "routes the event to an other service" do
        event_service.call

        expect(PaymentProviderCustomers::AdyenService).to have_received(:new)
        expect(payment_provider_service).to have_received(:preauthorise)
      end
    end

    context "when succeeded authorisation event for processed one-time payment" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response.json")
        File.read(path)
      end

      it "routes the event to an other service" do
        event_service.call

        expect(Invoices::Payments::AdyenService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when succeeded authorisation event for processed one-time payment belonging to a Payment Request" do
      let(:payment_service) { instance_double(PaymentRequests::Payments::AdyenService) }

      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response_payment_request.json")
        File.read(path)
      end

      before do
        allow(PaymentRequests::Payments::AdyenService).to receive(:new)
          .and_return(payment_service)
        allow(payment_service).to receive(:update_payment_status)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        event_service.call

        expect(PaymentRequests::Payments::AdyenService).to have_received(:new)
        expect(payment_service).to have_received(:update_payment_status)
      end
    end

    context "when succeeded authorisation event for processed one-time payment belonging to an invalid payable type" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response_invalid_payable.json")
        File.read(path)
      end

      it "routes the event to an other service" do
        expect {
          event_service.call
        }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
      end
    end

    context "when succeeded refund event" do
      let(:refund_service) { instance_double(CreditNotes::Refunds::AdyenService) }

      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_refund_response.json")
        File.read(path)
      end

      before do
        allow(CreditNotes::Refunds::AdyenService).to receive(:new)
          .and_return(refund_service)
        allow(refund_service).to receive(:update_status)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        event_service.call

        expect(CreditNotes::Refunds::AdyenService).to have_received(:new)
        expect(refund_service).to have_received(:update_status)
      end
    end
  end
end
