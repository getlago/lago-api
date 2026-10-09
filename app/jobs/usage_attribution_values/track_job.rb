# frozen_string_literal: true

module UsageAttributionValues
  class TrackJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_EVENTS"])
        :events
      else
        :default
      end
    end

    def perform(organization, entries)
      UsageAttributionValues::TrackService.call!(organization:, entries:)
    end
  end
end
