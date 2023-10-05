# frozen_string_literal: true

module Events
  class CreateJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_EVENTS'])
        :events   
      else
        :default
      end
    end

    def perform(organization, params, timestamp, metadata)
      result = Events::CreateService.new(
        organization:,
      ).call(
        params:,
        timestamp: Time.zone.at(timestamp.to_f),
        metadata:,
      )

      result.raise_if_error!
    end
  end
end
