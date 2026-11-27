# frozen_string_literal: true

module PaymentProviders
  module Flutterwave
    class HandleEventJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      retry_on(*PaymentProviders::FlutterwaveProvider::TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 6, jitter: 0.75)

      def perform(organization:, event:)
        PaymentProviders::Flutterwave::HandleEventService.call!(
          organization:,
          event_json: event
        )
      end
    end
  end
end
