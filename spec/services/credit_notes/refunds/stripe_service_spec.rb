# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::StripeService do
  subject(:stripe_service) { described_class.new(credit_note) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) { create(:stripe_customer, customer:) }
  let(:code) { "stripe_1" }
  let(:payment) do
    create(
      :payment,
      payment_provider: stripe_payment_provider,
      payment_provider_customer: stripe_customer,
      amount_cents: 200,
      amount_currency: "CHF",
      payable_payment_status: "succeeded",
      payable: credit_note.invoice
    )
  end

  let(:credit_note) do
    create(
      :credit_note,
      customer:,
      invoice:,
      refund_amount_cents: 134,
      refund_amount_currency: "CHF",
      refund_status: :pending
    )
  end

  let(:charge_amount_captured) { 200 }
  let(:charge_amount_refunded) { 0 }
  let(:stripe_charges) do
    Stripe::ListObject.construct_from(
      object: "list",
      url: "/v1/charges",
      has_more: false,
      data: [
        {
          id: "ch_123456",
          object: "charge",
          status: "succeeded",
          currency: "chf",
          amount: 200,
          amount_captured: charge_amount_captured,
          amount_refunded: charge_amount_refunded
        }
      ]
    )
  end

  describe "#create" do
    before do
      payment

      allow(Stripe::Charge).to receive(:list).and_return(stripe_charges)

      allow(Stripe::Refund).to receive(:create)
        .and_return(
          Stripe::Refund.construct_from(
            id: "re_123456",
            status: "succeeded",
            amount: 134,
            currency: "chf"
          )
        )
    end

    it "creates a stripe refund and a refund" do
      result = stripe_service.create

      expect(result).to be_success

      expect(result.refund.id).to be_present

      expect(result.refund.credit_note).to eq(credit_note)
      expect(result.refund.refundable).to eq(credit_note)
      expect(result.refund.reason).to eq("credit_note")
      expect(result.refund.payment).to eq(payment)
      expect(result.refund.payment_provider).to eq(stripe_payment_provider)
      expect(result.refund.payment_provider_customer).to eq(stripe_customer)
      expect(result.refund.amount_cents).to eq(134)
      expect(result.refund.amount_currency).to eq("CHF")
      expect(result.refund.status).to eq("succeeded")
      expect(result.refund.provider_refund_id).to eq("re_123456")

      expect(result.credit_note).to be_succeeded
      expect(result.credit_note.refunded_at).to be_present
    end

    it "call SegmentTrackJob" do
      stripe_service.create

      expect(SegmentTrackJob).to have_been_enqueued.with(
        membership_id: CurrentContext.membership,
        event: "refund_status_changed",
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          refund_status: "succeeded"
        }
      )
    end

    context "with a payment request for an invoice" do
      let(:payment_request) { create(:payment_request, payment_status: 1, customer: credit_note.customer) }
      let(:applied_payment_request) { create(:payment_request_applied_invoice, payment_request:, invoice: credit_note.invoice) }
      let(:payment) do
        create(
          :payment,
          payment_provider: stripe_payment_provider,
          payment_provider_customer: stripe_customer,
          amount_cents: 200,
          amount_currency: "CHF",
          payable_payment_status: "succeeded",
          payable: payment_request
        )
      end

      before { applied_payment_request }

      it "creates a stripe refund and a refund" do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.refund.id).to be_present

        expect(result.refund.credit_note).to eq(credit_note)
        expect(result.refund.payment).to eq(payment)
        expect(result.refund.payment_provider).to eq(stripe_payment_provider)
        expect(result.refund.payment_provider_customer).to eq(stripe_customer)
        expect(result.refund.amount_cents).to eq(134)
        expect(result.refund.amount_currency).to eq("CHF")
        expect(result.refund.status).to eq("succeeded")
        expect(result.refund.provider_refund_id).to eq("re_123456")

        expect(result.credit_note).to be_succeeded
        expect(result.credit_note.refunded_at).to be_present
      end
    end

    context "when the provider was disconnected and reconnected" do
      let(:reconnected_provider) { create(:stripe_provider, organization:, code: "stripe_reconnected") }
      let(:reconnected_customer) { create(:stripe_customer, customer:, payment_provider: reconnected_provider) }

      before do
        stripe_customer.discard!
        reconnected_customer
      end

      it "attaches the refund to the provider customer that holds the payment" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund.payment_provider_customer_id).to eq(stripe_customer.id)
      end
    end

    context "with an error on stripe" do
      let(:error_message) { "error" }

      before do
        allow(Stripe::Refund).to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new(error_message, {}, code: error_message))
      end

      it "delivers an error webhook" do
        result = stripe_service.create

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stripe_error")

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "credit_note.provider_refund_failure",
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: "error"
            }
          )
      end

      it "produces an activity log" do
        stripe_service.create

        expect(Utils::ActivityLog).to have_produced("credit_note.refund_failure").with(credit_note)
      end

      [
        CreditNotes::Refunds::StripeService::CHARGE_DISPUTED_ERROR,
        CreditNotes::Refunds::StripeService::CHARGE_ALREADY_REFUNDED_ERROR
      ].each do |code|
        context "when error is #{code}" do
          let(:error_message) { code }

          it "does not raise and marks the credit note as failed" do
            result = stripe_service.create

            expect(result).to be_success
            expect(result.refund).to be_nil
            expect(credit_note.reload.refund_status).to eq("failed")

            expect(SendWebhookJob).to have_been_enqueued
              .with(
                "credit_note.provider_refund_failure",
                credit_note,
                provider_customer_id: stripe_customer.provider_customer_id,
                provider_error: {message: error_message, error_code: error_message}
              )
          end
        end
      end

      context "when error is about non refundable payment method" do
        let(:error_message) { described_class::INVALID_PAYMENT_METHOD_ERROR }

        it "returns a success result" do
          result = stripe_service.create

          expect(result).to be_success

          expect(result.credit_note).to eq(credit_note)
          expect(result.refund).to be_nil

          expect(SendWebhookJob).to have_been_enqueued
            .with(
              "credit_note.provider_refund_failure",
              credit_note,
              provider_customer_id: stripe_customer.provider_customer_id,
              provider_error: {
                message: error_message,
                error_code: error_message
              }
            )
        end
      end
    end

    context "when credit note does not have a refund amount" do
      let(:credit_note) do
        create(
          :credit_note,
          customer:,
          refund_amount_cents: 0,
          refund_amount_currency: "CHF"
        )
      end

      it "does not create a refund" do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil

        expect(Stripe::Refund).not_to have_received(:create)
        expect(Stripe::Charge).not_to have_received(:list)
      end
    end

    context "when invoice does not have a payment" do
      let(:payment) { nil }

      it "does not create a refund" do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil

        expect(Stripe::Refund).not_to have_received(:create)
        expect(Stripe::Charge).not_to have_received(:list)
      end
    end

    context "when payment provider customer was discarded" do
      before { stripe_customer.discard }

      it "creates a stripe refund and a refund" do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.refund.id).to be_present

        expect(result.refund.credit_note).to eq(credit_note)
        expect(result.refund.payment).to eq(payment)
        expect(result.refund.payment_provider).to eq(stripe_payment_provider)
        expect(result.refund.payment_provider_customer).to eq(stripe_customer)
        expect(result.refund.amount_cents).to eq(134)
        expect(result.refund.amount_currency).to eq("CHF")
        expect(result.refund.status).to eq("succeeded")
        expect(result.refund.provider_refund_id).to eq("re_123456")

        expect(result.credit_note).to be_succeeded
        expect(result.credit_note.refunded_at).to be_present
      end
    end

    context "when dispute was lost" do
      let(:invoice) { create(:invoice, :dispute_lost, customer:, organization:) }

      it "does not create a refund" do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.credit_note).to eq(credit_note)
        expect(result.refund).to be_nil

        expect(Stripe::Refund).not_to have_received(:create)
      end
    end

    context "when a dispute is open on the invoice" do
      let(:invoice) { create(:invoice, :refund_blocked, customer:, organization:) }

      it "does not create a refund and marks the credit note as failed" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_nil
        expect(credit_note.reload.refund_status).to eq("failed")

        expect(Stripe::Refund).not_to have_received(:create)
      end

      it "does not query stripe for the charge" do
        stripe_service.create

        expect(Stripe::Charge).not_to have_received(:list)
      end

      it "delivers an error webhook" do
        stripe_service.create

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "credit_note.provider_refund_failure",
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "The charge is disputed and cannot be refunded",
              error_code: described_class::CHARGE_DISPUTED_ERROR
            }
          )
      end

      it "produces an activity log" do
        stripe_service.create

        expect(Utils::ActivityLog).to have_produced("credit_note.refund_failure").with(credit_note)
      end
    end

    context "when the charge is already fully refunded" do
      let(:charge_amount_refunded) { 200 }

      it "does not create a refund and marks the credit note as failed" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_nil
        expect(credit_note.reload.refund_status).to eq("failed")

        expect(Stripe::Refund).not_to have_received(:create)
      end

      it "delivers an error webhook" do
        stripe_service.create

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "credit_note.provider_refund_failure",
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "The charge has already been fully refunded",
              error_code: described_class::CHARGE_ALREADY_REFUNDED_ERROR
            }
          )
      end
    end

    context "when the charge has less refundable amount than the credit note" do
      let(:charge_amount_refunded) { 100 }

      it "does not refund the remainder" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_nil
        expect(credit_note.reload.refund_status).to eq("failed")

        expect(Stripe::Refund).not_to have_received(:create)
      end

      it "delivers an error webhook naming both amounts" do
        stripe_service.create

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "credit_note.provider_refund_failure",
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "The charge has only 100 cents left to refund, 134 are required",
              error_code: described_class::INSUFFICIENT_REFUNDABLE_AMOUNT_ERROR
            }
          )
      end
    end

    context "when the charge has exactly the credit note amount left" do
      let(:charge_amount_refunded) { 66 }

      it "creates the refund" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_present
        expect(Stripe::Refund).to have_received(:create)
      end
    end

    context "when the charge cannot be retrieved from stripe" do
      before do
        allow(Stripe::Charge).to receive(:list).and_raise(::Stripe::APIConnectionError.new("boom"))
      end

      it "falls back to attempting the refund" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_present
        expect(Stripe::Refund).to have_received(:create)
      end
    end

    context "when the payment intent has no succeeded charge" do
      let(:stripe_charges) do
        Stripe::ListObject.construct_from(object: "list", url: "/v1/charges", has_more: false, data: [])
      end

      it "falls back to attempting the refund" do
        result = stripe_service.create

        expect(result).to be_success
        expect(Stripe::Refund).to have_received(:create)
      end
    end

    context "when the payment intent carries a failed attempt" do
      let(:stripe_charges) do
        Stripe::ListObject.construct_from(
          object: "list",
          url: "/v1/charges",
          has_more: false,
          data: [
            {id: "ch_failed", object: "charge", status: "failed", amount: 200, amount_captured: 0, amount_refunded: 0},
            {id: "ch_ok", object: "charge", status: "succeeded", amount: 200, amount_captured: 200, amount_refunded: 200}
          ]
        )
      end

      it "decides on the succeeded charge" do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.refund).to be_nil
        expect(Stripe::Refund).not_to have_received(:create)
      end
    end

    context "when the payment has no provider payment id" do
      let(:payment) do
        create(
          :payment,
          payment_provider: stripe_payment_provider,
          payment_provider_customer: stripe_customer,
          amount_cents: 200,
          amount_currency: "CHF",
          payable_payment_status: "succeeded",
          payable: credit_note.invoice,
          provider_payment_id: nil
        )
      end

      it "does not list charges and attempts the refund" do
        stripe_service.create

        expect(Stripe::Charge).not_to have_received(:list)
        expect(Stripe::Refund).to have_received(:create)
      end
    end

    it "queries stripe for the charges of the payment intent" do
      stripe_service.create

      expect(Stripe::Charge).to have_received(:list).with(
        {payment_intent: payment.provider_payment_id, limit: 10},
        {api_key: stripe_payment_provider.secret_key}
      )
    end
  end

  describe "#update_status" do
    let(:refund) do
      create(:refund, credit_note:)
    end

    before { credit_note.pending! }

    it "updates the refund status" do
      result = stripe_service.update_status(
        provider_refund_id: refund.provider_refund_id,
        status: "succeeded"
      )

      expect(result).to be_success

      expect(result.refund).to eq(refund)
      expect(result.refund.status).to eq("succeeded")

      expect(result.credit_note).to be_succeeded
    end

    it "calls SegmentTrackJob" do
      stripe_service.update_status(
        provider_refund_id: refund.provider_refund_id,
        status: "succeeded"
      )

      expect(SegmentTrackJob).to have_been_enqueued.with(
        membership_id: CurrentContext.membership,
        event: "refund_status_changed",
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          refund_status: "succeeded"
        }
      )
    end

    context "when refund is not found" do
      let(:refund) { nil }

      it "returns an empty result" do
        result = stripe_service.update_status(
          provider_refund_id: "foo",
          status: "succeeded"
        )

        expect(result).to be_success
        expect(result.refund).to be_nil
      end

      context "with invoice id in metadata" do
        it "returns an empty result" do
          result = stripe_service.update_status(
            provider_refund_id: "foo",
            status: "succeeded",
            metadata: {lago_invoice_id: SecureRandom.uuid}
          )

          expect(result).to be_success
          expect(result.refund).to be_nil
        end

        context "when invoice belongs to lago" do
          let(:invoice) { create(:invoice) }

          it "returns a not found failure" do
            result = stripe_service.update_status(
              provider_refund_id: "re_123456",
              status: "succeeded",
              metadata: {lago_invoice_id: invoice.id}
            )

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq("stripe_refund_not_found")
          end
        end
      end
    end

    context "when status is not valid" do
      it "fails" do
        result = stripe_service.update_status(
          provider_refund_id: refund.provider_refund_id,
          status: "invalid"
        )

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:refund_status]).to include("value_is_invalid")
      end
    end

    context "when status is failed" do
      before do
        payment
      end

      it "delivers an error webhook" do
        result = stripe_service.update_status(
          provider_refund_id: refund.provider_refund_id,
          status: "failed"
        )

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("refund_failed")
        expect(result.error.error_message).to eq("Refund failed to perform")

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "credit_note.provider_refund_failure",
            credit_note,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "Payment refund failed",
              error_code: nil
            }
          )
      end

      it "produces an activity log" do
        stripe_service.update_status(
          provider_refund_id: refund.provider_refund_id,
          status: "failed"
        )

        expect(Utils::ActivityLog).to have_produced("credit_note.refund_failure").with(credit_note)
      end
    end
  end
end
