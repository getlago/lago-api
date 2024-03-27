# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleEventJob < ApplicationJob
      queue_as "providers"

      # NOTE: Sometimes, the stripe webhook is received before the DB update of the impacted resource
      retry_on BaseService::NotFoundFailure

      def perform(organization:, event:)
        result = PaymentProviders::StripeService.new.handle_event(
          organization:,
          event_json: event
        )
        result.raise_if_error!
      end
    end
  end
end
