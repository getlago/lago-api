# frozen_string_literal: true

module Events
  class CreateBatchJob < ApplicationJob
    queue_as :default

    def perform(organization, params, timestamp, metadata)
      result = Events::CreateBatchService.new.call(
        organization: organization,
        params: params,
        timestamp: Time.zone.at(timestamp),
        metadata: metadata,
      )

      result.raise_if_error!
    end
  end
end
