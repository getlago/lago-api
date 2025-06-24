# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class RegisterWebhookService < BaseService
      def call
        params = webhook_endpoint_shared_params
        params[:api_version] = ::Stripe.api_version

        stripe_webhook = ::Stripe::WebhookEndpoint.create(
          params,
          {api_key:}
        )

        payment_provider.update!(
          webhook_id: stripe_webhook.id,
          webhook_secret: stripe_webhook.secret
        )

        result.payment_provider = payment_provider
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
        deliver_error_webhook(action: "payment_provider.register_webhook", error: e)
        result
      rescue ::Stripe::InvalidRequestError => e
        raise if e.message != "You have reached the maximum of 16 test webhook endpoints."

        deliver_error_webhook(action: "payment_provider.register_webhook", error: e)
        result
      end
    end
  end
end
