# frozen_string_literal: true

module PaymentProviders
  class CancelPaymentAuthorizationJob < ApplicationJob
    queue_as "providers"

    def perform(payment_provider:, id:)
      case payment_provider.payment_type.to_s
      when "stripe"
        ::Stripe::PaymentIntent.cancel(id, {}, api_key: payment_provider.secret_key)
      else
        raise NotImplementedError.new("Cancelling payment authorization not implemented for #{provider}")
      end
    end
  end
end
