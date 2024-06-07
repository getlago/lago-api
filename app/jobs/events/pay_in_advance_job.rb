# frozen_string_literal: true

module Events
  class PayInAdvanceJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_EVENTS'])
        :events
      else
        :default
      end
    end

    def perform(event)
      Events::PayInAdvanceService.call(event:).raise_if_error!
    end
  end
end
