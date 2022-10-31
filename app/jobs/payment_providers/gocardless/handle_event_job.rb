# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(events:)
        result = PaymentProviders::GocardlessService.new.handle_event(events_json: events)
        result.throw_error
      end
    end
  end
end
