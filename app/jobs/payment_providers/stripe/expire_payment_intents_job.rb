# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class ExpirePaymentIntentsJob < ApplicationJob
      queue_as "providers"

      def perform(payment_provider)
        PaymentProviders::Stripe::ExpirePaymentIntentsService.call!(payment_provider)
      end
    end
  end
end
