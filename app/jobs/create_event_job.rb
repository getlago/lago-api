# frozen_string_literal: true

class CreateEventJob < ApplicationJob
  queue_as :default

  def perform(organization, params)
    # Do something later
  end
end
