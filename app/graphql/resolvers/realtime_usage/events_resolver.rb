# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class EventsResolver < BaseResolver
      description "Query the events counted on the usage-based charges of the organization, per period"

      type Types::RealtimeUsage::Events, null: false

      def resolve(**args)
        result = ::RealtimeUsage::Reports::EventsService.call(**report_filters(**args))

        result.success? ? result.events : result_error(result)
      end
    end
  end
end
