# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::StripeService do
  subject(:stripe_service) { described_class.new(invoice) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_method_id: "pm_123456") }
  let(:code) { "stripe_1" }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      total_paid_amount_cents:,
      currency: "EUR",
      ready_for_payment_processing: true
    )
  end

  let(:total_paid_amount_cents) { 0 }

  describe "#update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        provider_payment_id: "ch_123456"
      )
    end

    let(:stripe_payment) do
      PaymentProviders::StripeProvider::StripePayment.new(
        id: "ch_123456",
        status: "succeeded",
        metadata: {}
      )
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it "updates the payment and invoice status" do
      result = stripe_service.update_payment_status(
        organization_id: organization.id,
        status: "succeeded",
        stripe_payment:
      )

      expect(result).to be_success
      expect(result.payment.status).to eq("succeeded")
      expect(result.payment.payable_payment_status).to eq("succeeded")
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: invoice.total_amount_cents
      )
    end

    context "when status is failed" do
      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: "ch_123456",
          status: "canceled",
          metadata: {}
        )
      end

      it "updates the payment and invoice status" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "failed",
          stripe_payment:
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("failed")
        expect(result.payment.payable_payment_status).to eq("failed")
        expect(result.invoice.reload).to have_attributes(
          payment_status: "failed",
          ready_for_payment_processing: true
        )
      end
    end

    context "when invoice is already payment_succeeded" do
      before { invoice.payment_succeeded! }

      it "does not update the status of invoice and payment" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment:
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq("succeeded")
      end
    end

    context "with invalid status" do
      it "does not update the status of invoice and payment" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "foo-bar",
          stripe_payment:
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:payable_payment_status)
          expect(result.error.messages[:payable_payment_status]).to include("value_is_invalid")
        end
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }

      let(:stripe_payment) do
        PaymentProviders::StripeProvider::StripePayment.new(
          id: "ch_123456",
          status: "succeeded",
          metadata: {lago_invoice_id: invoice.id, payment_type: "one-time"}
        )
      end

      before do
        stripe_payment_provider
        stripe_customer
      end

      it "creates a payment and updates invoice payment status" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment:
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment.organization).to eq(organization)
          expect(result.payment.status).to eq("succeeded")
          expect(result.payment.payable_payment_status).to eq("succeeded")
          expect(result.invoice.reload).to have_attributes(
            payment_status: "succeeded",
            ready_for_payment_processing: false
          )
        end
      end

      context "when invoice is not found" do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: "ch_123456",
            status: "succeeded",
            metadata: {lago_invoice_id: "invalid", payment_type: "one-time"}
          )
        end

        it "raises a not found failure" do
          result = stripe_service.update_payment_status(
            organization_id: organization.id,
            status: "succeeded",
            stripe_payment:
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq("invoice_not_found")
          end
        end
      end
    end

    context "when payment is not found" do
      let(:payment) { nil }

      it "returns an empty result" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment:
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "with invoice id in metadata" do
        let(:stripe_payment) do
          PaymentProviders::StripeProvider::StripePayment.new(
            id: "ch_123456",
            status: "succeeded",
            metadata: {lago_invoice_id: SecureRandom.uuid}
          )
        end

        it "returns an empty result" do
          result = stripe_service.update_payment_status(
            organization_id: organization.id,
            status: "succeeded",
            stripe_payment:
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.payment).to be_nil
          end
        end

        context "when the invoice is found for organization" do
          let(:stripe_payment) do
            PaymentProviders::StripeProvider::StripePayment.new(
              id: "ch_123456",
              status: "succeeded",
              metadata: {lago_invoice_id: invoice.id}
            )
          end

          before do
            stripe_customer
            stripe_payment_provider
          end

          it "creates the missing payment and updates invoice status" do
            result = stripe_service.update_payment_status(
              organization_id: organization.id,
              status: "succeeded",
              stripe_payment:
            )

            expect(result).to be_success
            expect(result.payment.status).to eq("succeeded")
            expect(result.payment.payable_payment_status).to eq("succeeded")
            expect(result.invoice.reload).to have_attributes(
              payment_status: "succeeded",
              ready_for_payment_processing: false
            )

            expect(invoice.payments.count).to eq(1)
            payment = invoice.payments.first
            expect(payment).to have_attributes(
              payable: invoice,
              payment_provider_id: stripe_payment_provider.id,
              payment_provider_customer_id: stripe_customer.id,
              amount_cents: invoice.total_amount_cents,
              amount_currency: invoice.currency,
              provider_payment_id: "ch_123456",
              status: "succeeded"
            )
          end
        end
      end
    end

    context "when payment's payable belongs to another organization" do
      let(:invoice) { create(:invoice) }

      it "does not update the payment status" do
        result = stripe_service.update_payment_status(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment:
        )

        expect(result).to be_success
        expect(result.payment).to be_nil
        expect(invoice.reload.payment_status).to eq("pending")
        expect(payment.reload.status).to eq("pending")
      end
    end
  end
end
