# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(events_json:)
        result = PaymentProviders::GocardlessService.new.handle_event(events_json: events_json)
        result.throw_error if result.present?
      end
    end
  end
end
