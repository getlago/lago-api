# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Adyen::HandleEventService do
  subject(:event_service) { described_class.new(organization:, event_json:) }

  let_it_be(:organization) { create(:organization) }

  describe "#call" do
    let(:payment_service) { instance_double(Invoices::Payments::AdyenService) }
    let(:service_result) { Invoices::Payments::AdyenService::RESULTS.fetch(:update_payment_status).new }

    before do
      allow(Invoices::Payments::AdyenService).to receive(:call)
        .and_return(service_result)
      allow(PaymentProviderCustomers::AdyenService).to receive(:call)
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

        expect(PaymentProviderCustomers::AdyenService).to have_received(:call).with(:preauthorise, any_args)
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

        expect(Invoices::Payments::AdyenService).to have_received(:call).with(:update_payment_status, any_args)
      end

      it "passes the amount value as a dedicated kwarg for the Payment row to use" do
        event_service.call

        expect(Invoices::Payments::AdyenService).to have_received(:call).with(
          :update_payment_status, hash_including(amount_cents: 71)
        )
      end

      it "passes the organization of the event so the payable lookup is scoped" do
        event_service.call

        expect(Invoices::Payments::AdyenService).to have_received(:call).with(
          :update_payment_status, hash_including(organization_id: organization.id)
        )
      end
    end

    context "when succeeded one-time authorisation event in a currency with other decimals in Adyen" do
      let(:event_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response.json")
        item = JSON.parse(File.read(path))["notificationItems"].first["NotificationRequestItem"]
        item["amount"] = event_amount
        item["additionalData"]["metadata.lago_invoice_id"] = lago_invoice_id
        item.to_json
      end

      let(:lago_invoice_id) { "ec82efeb-88bb-44f8-ba30-0d55b3fd583a" }

      context "when the currency is IDR" do
        let(:event_amount) { {"currency" => "IDR", "value" => 12_345} }

        it "passes the amount in Lago minor units" do
          event_service.call

          expect(Invoices::Payments::AdyenService).to have_received(:call).with(
            :update_payment_status, hash_including(amount_cents: 1_234_500) # 12_345 * 100
          )
        end
      end

      context "when the currency is HUF" do
        let(:event_amount) { {"currency" => "HUF", "value" => 5_000_000} }

        it "passes the amount in Lago minor units" do
          event_service.call

          expect(Invoices::Payments::AdyenService).to have_received(:call).with(
            :update_payment_status, hash_including(amount_cents: 50_000) # 5_000_000 / 100
          )
        end
      end

      context "when the amount has no value" do
        let(:event_amount) { {"currency" => "IDR"} }

        it "passes a nil amount so the payment falls back to the invoice amount" do
          event_service.call

          expect(Invoices::Payments::AdyenService).to have_received(:call).with(
            :update_payment_status, hash_including(amount_cents: nil)
          )
        end
      end

      context "when Adyen captured a rounded IDR amount of an invoice with a sub-unit part" do
        let(:event_amount) { {"currency" => "IDR", "value" => 124} }
        let(:lago_invoice_id) { invoice.id }
        let(:customer) { create(:customer, organization:, payment_provider_code: "adyen_1") }
        let(:adyen_payment_provider) { create(:adyen_provider, organization:, code: "adyen_1") }
        let(:invoice) do
          create(
            :invoice,
            organization:,
            customer:,
            currency: "IDR",
            total_amount_cents: 12_350,
            total_paid_amount_cents: 0,
            ready_for_payment_processing: true
          )
        end

        before do
          create(:adyen_customer, customer:, payment_provider: adyen_payment_provider)
          allow(Invoices::Payments::AdyenService).to receive(:call).and_call_original
        end

        it "stores the captured amount on the payment and the invoice, without a cap at the amount due" do
          event_service.call

          payment = invoice.payments.sole
          expect(payment).to have_attributes(
            amount_cents: 12_400, # Adyen captured 124 rupiah = 124 * 100
            amount_currency: "IDR",
            payable_payment_status: "succeeded"
          )
          expect(invoice.reload).to have_attributes(
            payment_status: "succeeded",
            total_paid_amount_cents: 12_400,
            total_due_amount_cents: -50 # 12_350 invoiced - 12_400 paid
          )
        end
      end
    end

    context "when succeeded authorisation event for processed one-time payment belonging to a Payment Request" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response_payment_request.json")
        File.read(path)
      end

      before do
        allow(PaymentRequests::Payments::AdyenService).to receive(:call)
          .and_return(service_result)
      end

      it "routes the event to an other service" do
        event_service.call

        expect(PaymentRequests::Payments::AdyenService).to have_received(:call).with(:update_payment_status, any_args)
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

    context "when chargeback event" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/chargeback_lost_event.json")
        File.read(path)
      end

      let(:customer) { create(:customer, organization:) }
      let(:invoice) { create(:invoice, organization:, customer:, status: :finalized, payment_status: :succeeded) }

      context "when the disputed payment exists" do
        before do
          create(:payment, payable: invoice, organization:, provider_payment_id: "9913333333333333")
        end

        it "marks the invoice payment dispute as lost" do
          result = event_service.call

          expect(result).to be_success
          expect(invoice.reload.payment_dispute_lost_at).to eq(Time.zone.parse("2020-03-13T11:35:42+01:00"))
        end
      end

      context "when the disputed payment is unknown" do
        it "raises a not found failure" do
          expect { event_service.call }.to raise_error(BaseService::NotFoundFailure)
        end
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
          .with(hash_including(organization_id: organization.id, status: :succeeded))
      end
    end

    context "when succeeded refund failed event" do
      let(:refund_service) { instance_double(CreditNotes::Refunds::AdyenService) }
      let(:service_result) { BaseService::Result.new }

      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem")
          &.merge("eventCode" => "REFUND_FAILED", "success" => "true").to_json
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

      it "routes the event to the refund service scoped to the organization" do
        event_service.call

        expect(refund_service).to have_received(:update_status)
          .with(hash_including(organization_id: organization.id, status: :failed))
      end
    end

    context "when succeeded cancellation event" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_cancellation_response.json")
        File.read(path)
      end

      let(:invoice) { create(:invoice, organization:) }

      before do
        create(:payment, payable: invoice, organization:,
          provider_payment_id: "PSPREF123", payable_payment_status: :pending,
          status: "Authorised")
      end

      it "routes the event to the invoice payments service with originalReference" do
        event_service.call

        expect(Invoices::Payments::AdyenService).to have_received(:call).with(
          :update_payment_status,
          organization_id: organization.id,
          provider_payment_id: "PSPREF123",
          status: "Cancelled",
          metadata: {lago_payable_type: "Invoice"}
        )
      end
    end

    context "when cancellation event references a payment from another organization" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_cancellation_response.json")
        File.read(path)
      end

      before do
        other_organization = create(:organization)
        invoice = create(:invoice, organization: other_organization, customer: create(:customer, organization: other_organization))
        create(:payment, payable: invoice, organization: other_organization,
          provider_payment_id: "PSPREF123", payable_payment_status: :pending,
          status: "Authorised")
      end

      it "does not route the event to a payment service" do
        event_service.call

        expect(Invoices::Payments::AdyenService).not_to have_received(:call)
      end
    end

    context "when failed cancellation event" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem")
          &.merge("success" => "false").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_cancellation_response.json")
        File.read(path)
      end

      it "does not route the event to a payment service" do
        event_service.call

        expect(Invoices::Payments::AdyenService).not_to have_received(:call)
      end
    end

    context "when cancellation event references an unknown payment" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_cancellation_response.json")
        File.read(path)
      end

      it "does not route the event to a payment service" do
        event_service.call

        expect(Invoices::Payments::AdyenService).not_to have_received(:call)
      end
    end

    context "when cancellation event is for a payment request payment" do
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      let(:event_response_json) do
        path = Rails.root.join("spec/fixtures/adyen/webhook_cancellation_response.json")
        File.read(path)
      end

      let(:customer) { create(:customer, organization:) }
      let(:payment_request) { create(:payment_request, organization:, customer:) }

      before do
        create(:payment, payable: payment_request, organization:, customer:,
          provider_payment_id: "PSPREF123", payable_payment_status: :pending,
          status: "Authorised")

        allow(PaymentRequests::Payments::AdyenService).to receive(:call)
          .and_return(service_result)
      end

      it "routes to the payment request payments service" do
        event_service.call

        expect(PaymentRequests::Payments::AdyenService).to have_received(:call).with(
          :update_payment_status,
          organization_id: organization.id,
          provider_payment_id: "PSPREF123",
          status: "Cancelled",
          metadata: {lago_payable_type: "PaymentRequest"}
        )
      end
    end

    context "when ignored event" do
      let(:refund_service) { instance_double(CreditNotes::Refunds::AdyenService) }
      let(:event_json) do
        JSON.parse(event_response_json)["notificationItems"]
          .first&.dig("NotificationRequestItem").to_json
      end

      %w[report_available recurring_contract offer_closed].each do |event_type|
        let(:event_response_json) do
          path = Rails.root.join("spec/fixtures/adyen/webhook_#{event_type}_response.json")
          File.read(path)
        end

        before do
          allow(CreditNotes::Refunds::AdyenService).to receive(:new)
            .and_return(refund_service)
          allow(refund_service).to receive(:update_status)
            .and_return(true)
        end

        it "does not route the event to an other service" do
          event_service.call

          expect(CreditNotes::Refunds::AdyenService).not_to have_received(:new)
          expect(refund_service).not_to have_received(:update_status)
        end
      end
    end
  end
end
