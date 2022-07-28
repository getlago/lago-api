# frozen_string_literal: true

module Events
  class CreateBatchJob < ApplicationJob
    queue_as :default

    def perform(organization, params, timestamp, metadata)
      result = EventsService.new.batch_create(
        organization: organization,
        params: params,
        timestamp: Time.zone.at(timestamp),
        metadata: metadata,
      )

      result.throw_error unless result.success?
    end
  end
end
