# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleEventJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      # NOTE: Sometimes, the stripe webhook is received before the DB update of the impacted resource
      retry_on BaseService::NotFoundFailure

      def perform(organization:, event:)
        result = PaymentProviders::Stripe::HandleEventService.call(
          organization:,
          event_json: event
        )
        result.raise_if_error!
      rescue BaseService::ServiceFailure => e
        # If the payment method wasn't attached to the customer, there is no need to retry to make it the default method
        raise e unless e.message.include?("The customer does not have a payment method with the ID")
      end
    end
  end
end
