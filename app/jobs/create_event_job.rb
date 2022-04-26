# frozen_string_literal: true

class CreateEventJob < ApplicationJob
  queue_as :default

  def perform(organization, params, timestamp)
    result = EventsService.new.create(
      organization: organization,
      params: params,
      timestamp: timestamp,
    )

    raise result.throw_error unless result.success?
  end
end
