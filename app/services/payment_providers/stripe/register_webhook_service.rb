# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class RegisterWebhookService < BaseService
      def call
        stripe_webhook = ::Stripe::WebhookEndpoint.create(
          {
            url: webhook_end_point,
            enabled_events: PaymentProviders::StripeProvider::WEBHOOKS_EVENTS,
          },
          {api_key:},
        )

        payment_provider.update!(
          webhook_id: stripe_webhook.id,
          webhook_secret: stripe_webhook.secret,
        )

        result.payment_provider = payment_provider
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ::Stripe::AuthenticationError => e
        deliver_error_webhook(action: 'payment_provider.register_webhook', error: e)
        result
      end

      private

      def webhook_end_point
        URI.join(
          ENV['LAGO_API_URL'],
          "webhooks/stripe/#{organization_id}?code=#{URI.encode_www_form_component(payment_provider.code)}"
        )
      end
    end
  end
end
