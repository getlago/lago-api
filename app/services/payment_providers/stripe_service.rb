# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    WEBHOOKS_ENVENTS = [
      'charge.failed',
      'charge.succeeded',
    ].freeze

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
        PaymentProviders::Stripe::RegisterWebhookJob.perform_later(stripe_provider)
      end

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def register_webhook(stripe_provider)
      organization_id = stripe_provider.organization_id

      stripe_webhook = ::Stripe::WebhookEndpoint.create(
        {
          url: URI.join(ENV['LAGO_API_URL'], "webhooks/stripe/#{organization_id}"),
          enabled_events: WEBHOOKS_ENVENTS,
        },
        { api_key: stripe_provider.secret_key },
      )

      stripe_provider.update!(
        webhook_id: stripe_webhook.id,
        webhook_secret: stripe_webhook.secret,
      )

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def handle_incoming_webhook(organization_id:, params:, signature:)
      organization = Organization.find_by(id: organization_id)

      event = ::Stripe::Webhook.construct_event(
        params,
        signature,
        organization&.stripe_payment_provider&.webhook_secret,
      )

      PaymentProviders::Stripe::HandleEventJob.perform_later(event.to_json)

      result.event = event
      result
    rescue JSON::ParserError
      result.fail!('webhook_error', 'Invalid payload')
    rescue ::Stripe::SignatureVerificationError
      result.fail!('webhook_error', 'Invalid signature')
    end

    def handle_event(event_json)
      event = ::Stripe::Event.construct_from(event_json)
      return result.fail!('invalid_stripe_event_type') unless WEBHOOKS_ENVENTS.include?(event.type)

      Invoices::Payments::StripeService
        .new.update_status(
          provider_payment_id: event.data.object.id,
          status: event.data.object.status,
        )
    end
  end
end
