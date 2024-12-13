# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::StripeService, type: :service do
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
      currency: "EUR",
      ready_for_payment_processing: true
    )
  end

  describe "#generate_payment_url" do
    before do
      stripe_payment_provider
      stripe_customer

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    it "generates payment url" do
      stripe_service.generate_payment_url

      expect(::Stripe::Checkout::Session).to have_received(:create)
    end

    context "when invoice is payment_succeeded" do
      before { invoice.payment_succeeded! }

      it "does not generate payment url" do
        stripe_service.generate_payment_url

        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context "when invoice is voided" do
      before { invoice.voided! }

      it "does not generate payment url" do
        stripe_service.generate_payment_url

        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    context "with #payment_url_payload" do
      let(:payment_url_payload) { stripe_service.__send__(:payment_url_payload) }
      let(:payload) do
        {
          line_items: [
            {
              quantity: 1,
              price_data: {
                currency: invoice.currency.downcase,
                unit_amount: invoice.total_amount_cents,
                product_data: {
                  name: invoice.number
                }
              }
            }
          ],
          mode: "payment",
          success_url: stripe_service.__send__(:success_redirect_url),
          customer: customer.stripe_customer.provider_customer_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          payment_intent_data: {
            description: stripe_service.__send__(:description),
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type,
              payment_type: "one-time"
            }
          }
        }
      end

      it "returns the payload" do
        expect(payment_url_payload).to eq(payload)
      end
    end
  end

  describe ".update_payment_status" do
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
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false
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
          expect(result.error.messages.keys).to include(:payment_status)
          expect(result.error.messages[:payment_status]).to include("value_is_invalid")
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
          expect(result.payment.status).to eq("succeeded")
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
  end
end
