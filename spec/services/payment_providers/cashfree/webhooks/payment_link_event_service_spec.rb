# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Cashfree::Webhooks::PaymentLinkEventService do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:event_json) { File.read("spec/fixtures/cashfree/payment_link_event_payment.json") }

  let(:payment_service) { instance_double(Invoices::Payments::CashfreeService) }
  let(:service_result) { Invoices::Payments::CashfreeService::RESULTS.fetch(:update_payment_status).new }

  describe "#call" do
    context "when succeeded payment event" do
      before do
        allow(Invoices::Payments::CashfreeService).to receive(:call)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        webhook_service.call

        expect(Invoices::Payments::CashfreeService).to have_received(:call)
          .with(:update_payment_status, anything)
      end

      it "passes the paid amount converted from major units to cents as a dedicated kwarg" do
        webhook_service.call

        expect(Invoices::Payments::CashfreeService).to have_received(:call).with(
          :update_payment_status, hash_including(amount_cents: 5500)
        )
      end
    end

    context "when succeeded payment_request event" do
      let(:event_json) do
        path = Rails.root.join("spec/fixtures/cashfree/payment_link_event_payment_request.json")
        File.read(path)
      end

      before do
        allow(PaymentRequests::Payments::CashfreeService).to receive(:call)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        webhook_service.call

        expect(PaymentRequests::Payments::CashfreeService).to have_received(:call).with(
          :update_payment_status, hash_including(organization_id: organization.id, status: "PAID")
        )
      end
    end
  end
end
