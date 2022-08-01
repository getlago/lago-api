# frozen_string_literal: true

class CreateEventJob < ApplicationJob
  queue_as :default

  def perform(organization, params, timestamp, metadata)
    result = Events::CreateService.new.create(
      organization: organization,
      params: params,
      timestamp: timestamp,
      metadata: metadata,
    )

    result.throw_error unless result.success?
  end
end
