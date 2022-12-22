# frozen_string_literal: true

class CreateEventJob < ApplicationJob
  queue_as :default

  def perform(organization, params, timestamp, metadata)
    result = Events::CreateService.new.call(
      organization: organization,
      params: params,
      timestamp: timestamp,
      metadata: metadata,
    )

    result.raise_if_error!
  end
end
