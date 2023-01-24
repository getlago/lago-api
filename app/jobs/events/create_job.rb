# frozen_string_literal: true

module Events
  class CreateJob < ApplicationJob
    queue_as :default

    def perform(organization, params, timestamp, metadata)
      result = Events::CreateService.new.call(
        organization:,
        params:,
        timestamp: Time.zone.at(timestamp),
        metadata:,
      )

      result.raise_if_error!
    end
  end
end
