# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class RefundExpiredPaymentService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        # Close the invoice so it remains invisible to the customer
        # and is not considered an accounts receivable.
        invoice.update!(status: :closed)

        payment = invoice.payments.order(created_at: :desc).first
        return result unless payment

        refund_payment(payment)

        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def refund_payment(payment)
        provider = payment.payment_provider

        case provider
        when PaymentProviders::StripeProvider
          refund_stripe(payment, provider)
        when PaymentProviders::AdyenProvider
          refund_adyen(payment, provider)
        when PaymentProviders::GocardlessProvider
          refund_gocardless(payment, provider)
        end

        # Cashfree, Flutterwave, and Moneyhash do not have refund support yet
      end

      def refund_stripe(payment, provider)
        ::Stripe::Refund.create(
          {
            payment_intent: payment.provider_payment_id,
            amount: payment.amount_cents,
            reason: :requested_by_customer,
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              lago_refund_reason: "activation_expired"
            }
          },
          {
            api_key: provider.secret_key,
            idempotency_key: "activation-refund-#{payment.id}"
          }
        )
      end

      def refund_adyen(payment, provider)
        client = ::Adyen::Client.new(
          api_key: provider.api_key,
          env: provider.environment,
          live_url_prefix: provider.live_prefix
        )

        client.checkout.modifications_api.refund_captured_payment(
          payment.provider_payment_id,
          Lago::Adyen::Params.new(
            merchantAccount: provider.merchant_account,
            amount: {
              value: payment.amount_cents,
              currency: payment.amount_currency.upcase
            },
            reference: "activation-refund-#{payment.id}"
          ).to_h
        )
      end

      def refund_gocardless(payment, provider)
        client = GoCardlessPro::Client.new(
          access_token: provider.access_token,
          environment: provider.environment
        )

        client.refunds.create(
          params: {
            amount: payment.amount_cents,
            total_amount_confirmation: payment.amount_cents,
            metadata: {
              lago_invoice_id: invoice.id,
              reason: "activation_expired"
            },
            links: {
              payment: payment.provider_payment_id
            }
          },
          headers: {
            "Idempotency-Key" => "activation-refund-#{payment.id}"
          }
        )
      end
    end
  end
end
