# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(event)
        result = PaymentProviders::StripeService.new.handle_event(event)
        result.throw_error
      end
    end
  end
end
