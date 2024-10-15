# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    class HandleEventJob < ApplicationJob
      queue_as 'providers'

      def perform(organization: nil, events_json: nil, event_json: nil)
        # NOTE: temporary keeps both events_json and event_json to avoid errors during the deployment
        if events_json.present?
          JSON.parse(events_json)['events'].each do |event|
            PaymentProviders::Gocardless::HandleEventJob.perform_later(event_json: event.to_json)
          end

          return
        end

        PaymentProviders::Gocardless::HandleEventService.call(event_json:).raise_if_error!
      end
    end
  end
end
