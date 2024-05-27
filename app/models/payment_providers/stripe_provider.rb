# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://stripe.com/'

    # NOTE: find the complete list of event types at https://stripe.com/docs/api/events/types
    WEBHOOKS_EVENTS = [
      'setup_intent.succeeded',
      'payment_intent.payment_failed',
      'payment_intent.succeeded',
      'payment_method.detached',
      'charge.refund.updated',
      'customer.updated',
      'charge.succeeded',
      'charge.dispute.closed'
    ].freeze

    validates :secret_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    settings_accessors :webhook_id
    secrets_accessors :secret_key
  end
end
