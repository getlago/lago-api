# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::GeneratePaymentUrlService do
  subject(:stripe_service) { described_class.new(invoice:, payment_intent:) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) do
    create(:stripe_customer, customer:, payment_method_id: "pm_123456", payment_provider: stripe_payment_provider)
  end
  let(:code) { "stripe_1" }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      total_paid_amount_cents: 0,
      currency: "EUR",
      ready_for_payment_processing: true
    )
  end
  let(:payment_intent) { create(:payment_intent) }

  describe "#call" do
    before do
      stripe_payment_provider
      stripe_customer

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    it "generates a payment url" do
      stripe_service.call

      expect(::Stripe::Checkout::Session).to have_received(:create)
        .with({
          line_items: [
            {
              quantity: 1,
              price_data: {
                currency: invoice.currency.downcase,
                unit_amount: invoice.total_due_amount_cents,
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
          expires_at: payment_intent.expires_at.to_i,
          payment_intent_data: {
            description: stripe_service.__send__(:description),
            setup_future_usage: "off_session",
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type,
              payment_type: "one-time"
            }
          }
        }, {
          api_key: stripe_payment_provider.secret_key,
          idempotency_key: "payment-intent-#{payment_intent.id}"
        })
    end

    context "when customer is from India" do
      let(:customer) { create(:customer, payment_provider_code: code, country: "IN") }

      it "generates a payment url" do
        stripe_service.call

        expect(::Stripe::Checkout::Session).to have_received(:create)
          .with({
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: invoice.currency.downcase,
                  unit_amount: invoice.total_due_amount_cents,
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
            expires_at: payment_intent.expires_at.to_i,
            payment_intent_data: {
              description: stripe_service.__send__(:description),
              setup_future_usage: nil,
              metadata: {
                lago_customer_id: customer.id,
                lago_invoice_id: invoice.id,
                invoice_issuing_date: invoice.issuing_date.iso8601,
                invoice_type: invoice.invoice_type,
                payment_type: "one-time"
              }
            }
          }, {
            api_key: stripe_payment_provider.secret_key,
            idempotency_key: "payment-intent-#{payment_intent.id}"
          })
      end
    end

    context "when customer can use crypto" do
      let(:stripe_customer) do
        create(
          :stripe_customer,
          customer:, payment_method_id: "pm_123456", payment_provider: stripe_payment_provider,
          provider_payment_methods: ["crypto"]
        )
      end

      it "generates a payment url" do
        stripe_service.call

        expect(::Stripe::Checkout::Session).to have_received(:create)
          .with({
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: invoice.currency.downcase,
                  unit_amount: invoice.total_due_amount_cents,
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
            expires_at: payment_intent.expires_at.to_i,
            payment_intent_data: {
              description: stripe_service.__send__(:description),
              setup_future_usage: nil,
              metadata: {
                lago_customer_id: customer.id,
                lago_invoice_id: invoice.id,
                invoice_issuing_date: invoice.issuing_date.iso8601,
                invoice_type: invoice.invoice_type,
                payment_type: "one-time"
              }
            }
          }, {
            api_key: stripe_payment_provider.secret_key,
            idempotency_key: "payment-intent-#{payment_intent.id}"
          })
      end
    end

    context "with an error on Stripe" do
      before do
        allow(::Stripe::Checkout::Session).to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new("error", {}))
      end

      it "returns a failed result" do
        result = stripe_service.call

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq("Stripe")
        expect(result.error.error_message).to eq("error")
      end
    end
  end
end
