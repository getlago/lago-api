# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class RegisterWebhookJob < ApplicationJob
      queue_as 'billing'

      def perform(stripe_provider)
        result = PaymentProviders::StripeService.new.register_webhook(stripe_provider)
        result.throw_error
      end
    end
  end
end
