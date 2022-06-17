# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    def create_or_update(**args)
      stripe_provider = PaymentProviders::StripeProvider.find_or_initialize_by(
        organization_id: args[:organization_id],
      )

      secret_key = stripe_provider.secret_key

      stripe_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      stripe_provider.create_customers = args[:create_customers]
      stripe_provider.send_zero_amount_invoice = args[:send_zero_amount_invoice]
      stripe_provider.save!

      if secret_key != stripe_provider.secret_key
        # TODO: Unregister previously configured webhooks
        PaymentProviders::RegisterStripeWebhookJob.perform_later(stripe_provider)
      end

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def register_webhook(stripe_provider)
      stripe_webhook = Stripe::WebhookEndpoint.create(
        {
          url: URI.join(LAGO_API_URL, 'webhooks/stripe'),
          enabled_events: [
            'charge.failed',
            'charge.succeeded',
          ],
        },
        { api_key: stripe_provider.secret_key },
      )

      stripe_provider.update!(webhook_id: stripe_webhook.id)

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
