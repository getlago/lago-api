# frozen_string_literal: true

module Subscriptions
  module Payments
    class CancelService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        payment = invoice.payments.where(payable_payment_status: %w[pending processing]).order(created_at: :desc).first
        return result unless payment

        provider = payment.payment_provider
        return result unless provider

        cancel_with_provider(payment, provider)

        result
      rescue => e
        # Best-effort cancellation — log and continue
        Rails.logger.warn("Payment cancellation failed for payment #{payment&.id}: #{e.message}")
        result
      end

      private

      attr_reader :invoice

      def cancel_with_provider(payment, provider)
        case provider
        when PaymentProviders::StripeProvider
          ::Stripe::PaymentIntent.cancel(
            payment.provider_payment_id,
            {},
            {api_key: provider.secret_key}
          )
        when PaymentProviders::AdyenProvider
          adyen_client(provider).checkout.modifications_api.cancel_authorised_payment_by_psp_reference(
            Lago::Adyen::Params.new(merchantAccount: provider.merchant_account).to_h,
            payment.provider_payment_id
          )
        when PaymentProviders::GocardlessProvider
          gocardless_client(provider).payments.cancel(payment.provider_payment_id)
        end
      end

      def adyen_client(provider)
        ::Adyen::Client.new(
          api_key: provider.api_key,
          env: provider.environment,
          live_url_prefix: provider.live_prefix
        )
      end

      def gocardless_client(provider)
        GoCardlessPro::Client.new(
          access_token: provider.access_token,
          environment: provider.environment
        )
      end
    end
  end
end
