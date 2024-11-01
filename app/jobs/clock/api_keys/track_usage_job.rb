# frozen_string_literal: true

module Clock
  module ApiKeys
    class TrackUsageJob < ApplicationJob
      include SentryCronConcern

      queue_as 'clock'

      def perform
        ::ApiKeys::TrackUsageService.call
      end
    end
  end
end
