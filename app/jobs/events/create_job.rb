# frozen_string_literal: true

module Events
  class CreateJob < ApplicationJob
    queue_as :default

    def perform(organization, params, timestamp, metadata)
      Events::CreateService.new.call(
        organization: organization,
        params: params,
        timestamp: Time.zone.at(timestamp),
        metadata: metadata,
      )
    end
  end
end
