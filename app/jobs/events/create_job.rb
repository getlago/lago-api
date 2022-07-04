# frozen_string_literal: true

module Events
  class CreateJob < ApplicationJob
    queue_as :default

    def perform(organization, params, timestamp, metadata)
      result = EventsService.new.create(
        organization: organization,
        params: params,
        timestamp: Time.zone.at(timestamp),
        metadata: metadata,
      )

      result.throw_error unless result.success?
    end
  end
end
