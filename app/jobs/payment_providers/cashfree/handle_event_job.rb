# frozen_string_literal: true

module PaymentProviders
  module Cashfree
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(event_json:)
        result = PaymentProviders::CashfreeService.new.handle_event(event_json:)
        result.raise_if_error!
      end
    end
  end
end
