# frozen_string_literal: true

module PaymentProviders
  module Cashfree
    class HandleEventJob < ApplicationJob
      queue_as "providers"

      def perform(organization:, event:)
        PaymentProviders::Cashfree::HandleEventService.call!(
          organization:,
          event_json: event
        )
      end
    end
  end
end
