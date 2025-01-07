# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(payment_request) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:adyen_payment_provider) { create(:adyen_provider, organization:, code:) }
  let(:adyen_customer) { create(:adyen_customer, customer:) }
  let(:adyen_client) { instance_double(Adyen::Client) }
  let(:payments_api) { Adyen::PaymentsApi.new(adyen_client, 70) }
  let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
  let(:payments_response) { generate(:adyen_payments_response) }
  let(:payment_methods_response) { generate(:adyen_payment_methods_response) }
  let(:code) { "adyen_1" }

  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "USD",
      invoices: [invoice_1, invoice_2]
    )
  end

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  describe "#generate_payment_url" do
    let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }
    let(:payment_links_response) { generate(:adyen_payment_links_response) }

    before do
      adyen_payment_provider
      adyen_customer

      allow(Adyen::Client).to receive(:new)
        .and_return(adyen_client)
      allow(adyen_client).to receive(:checkout)
        .and_return(checkout)
      allow(checkout).to receive(:payment_links_api)
        .and_return(payment_links_api)
      allow(payment_links_api).to receive(:payment_links)
        .and_return(payment_links_response)
    end

    it "generates payment url" do
      freeze_time do
        adyen_service.generate_payment_url

        expect(payment_links_api)
          .to have_received(:payment_links)
          .with(
            {
              amount: {
                currency: "USD",
                value: 799
              },
              applicationInfo: {
                externalPlatform: {integrator: "Lago", name: "Lago"},
                merchantApplication: {name: "Lago"}
              },
              expiresAt: Time.current + 70.days,
              merchantAccount: adyen_payment_provider.merchant_account,
              metadata: {
                lago_customer_id: customer.id,
                lago_payable_id: payment_request.id,
                lago_payable_type: "PaymentRequest",
                payment_type: "one-time"
              },
              recurringProcessingModel: "UnscheduledCardOnFile",
              reference: "Overdue invoices",
              returnUrl: adyen_payment_provider.success_redirect_url,
              shopperEmail: customer.email,
              shopperReference: customer.external_id,
              storePaymentMethodMode: "enabled"
            }
          )
      end
    end

    context "when payment request is payment_succeeded" do
      before { payment_request.payment_succeeded! }

      it "does not generate payment url" do
        adyen_service.generate_payment_url

        expect(payment_links_api).not_to have_received(:payment_links)
      end
    end
  end

  describe "#update_payment_status" do
    subject(:result) do
      adyen_service.update_payment_status(provider_payment_id:, status:)
    end

    let(:status) { "Authorised" }

    let(:payment) do
      create(
        :payment,
        :adyen_payment,
        payable: payment_request,
        provider_payment_id:,
        status: "Pending"
      )
    end

    let(:provider_payment_id) { "ch_123456" }

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(SegmentTrackJob).to receive(:perform_later)
      payment
    end

    it "updates the payment, payment_request and invoices payment_status", :aggregate_failures do
      expect(result).to be_success
      expect(result.payment.status).to eq(status)

      expect(result.payable.reload).to be_payment_succeeded
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_1.ready_for_payment_processing).to eq(false)
      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)
    end

    it "does not send payment requested email" do
      expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
    end

    context "when the payment request belongs to a dunning campaign" do
      let(:customer) do
        create(
          :customer,
          payment_provider_code: code,
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: Time.zone.now
        )
      end

      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 799,
          amount_currency: "USD",
          invoices: [invoice_1, invoice_2],
          dunning_campaign: create(:dunning_campaign)
        )
      end

      it "resets the customer dunning campaign counters" do
        expect { result && customer.reload }
          .to change(customer, :last_dunning_campaign_attempt).to(0)
          .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

        expect(result).to be_success
      end

      context "when status is failed" do
        let(:status) { "failed" }

        it "doest not reset the customer dunning campaign counters" do
          expect { result && customer.reload }
            .to not_change(customer, :last_dunning_campaign_attempt)
            .and not_change { customer.last_dunning_campaign_attempt_at&.to_i }

          expect(result).to be_success
        end
      end
    end

    context "when status is failed" do
      let(:status) { "Refused" }

      it "updates the payment, payment_request and invoices status", :aggregate_failures do
        expect(result).to be_success
        expect(result.payment.status).to eq(status)

        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.ready_for_payment_processing).to eq(true)

        expect(invoice_1.reload).to be_payment_failed
        expect(invoice_1.ready_for_payment_processing).to eq(true)

        expect(invoice_2.reload).to be_payment_failed
        expect(invoice_2.ready_for_payment_processing).to eq(true)
      end

      it "sends a payment requested email" do
        expect { result }.to have_enqueued_mail(PaymentRequestMailer, :requested)
          .with(params: {payment_request:}, args: [])
      end
    end

    context "when payment_request and invoices is already payment_succeeded" do
      let(:status) do
        %w[Authorised SentForSettle SettleScheduled Settled Refunded].sample
      end

      before do
        payment_request.payment_succeeded!
        invoice_1.payment_succeeded!
        invoice_2.payment_succeeded!
      end

      it "does not update the status of invoices, payment_request and payment" do
        expect { result }
          .to not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment_request.reload.payment_status }
          .and not_change { payment.reload.status }

        expect(result).to be_success
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "with invalid status" do
      let(:status) { "invalid-status" }

      it "does not update the payment_status of payment_request, invoices and payment" do
        expect { result }
          .to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and change { payment.reload.status }.to(status)
      end

      it "returns an error", :aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payment_status)
        expect(result.error.messages[:payment_status]).to include("value_is_invalid")
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }
      let(:status) { "succeeded" }

      before do
        adyen_payment_provider
        adyen_customer
      end

      it "creates a payment and updates payment request and invoices payment status", :aggregate_failures do
        result = adyen_service.update_payment_status(
          provider_payment_id:,
          status:,
          metadata: {
            lago_payable_id: payment_request.id,
            lago_payable_type: "PaymentRequest",
            payment_type: "one-time"
          }
        )

        expect(result).to be_success
        expect(result.payment.status).to eq(status)

        expect(result.payable).to be_payment_succeeded
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(invoice_1.reload).to be_payment_succeeded
        expect(invoice_1.ready_for_payment_processing).to eq(false)

        expect(invoice_2.reload).to be_payment_succeeded
        expect(invoice_2.ready_for_payment_processing).to eq(false)
      end
    end
  end
end
