# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class RefreshWebhookJob < ApplicationJob
      queue_as "providers"

      def perform(stripe_provider)
        result = PaymentProviders::StripeService.new.refresh_webhook(
          stripe_provider:
        )
        result.raise_if_error!
      end
    end
  end
end
