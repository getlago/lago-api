# frozen_string_literal: true

module PaymentProviders
  class RegisterStripeWebhookJob < ApplicationJob
    queue_as 'billing'

    def perform(stripe_provider)
      result = PaymentProviders::StripeService.new.register_webhook(stripe_provider)
      result.throw_error
    end
  end
end
