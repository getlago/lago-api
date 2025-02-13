# frozen_string_literal: true

module PaymentProviders
  module Adyen
    class HandleEventJob < ApplicationJob
      queue_as "providers"

      def perform(organization:, event_json:)
        result = PaymentProviders::AdyenService.new.handle_event(organization:, event_json:)
        result.raise_if_error!
      end
    end
  end
end
