# frozen_string_literal: true

module Clock
  module ApiKeys
    class TrackUsageJob < ApplicationJob
      include SentryCronConcern

      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
          :clock_worker
        else
          :clock
        end
      end

      def perform
        ::ApiKeys::TrackUsageService.call
      end
    end
  end
end
