# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(organization:, event:)
        result = PaymentProviders::StripeService.new.handle_event(
          organization: organization,
          event_json: event,
        )
        result.raise_if_error!
      end
    end
  end
end
