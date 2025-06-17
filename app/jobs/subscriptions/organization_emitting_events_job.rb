# frozen_string_literal: true

module Subscriptions
  class OrganizationEmittingEventsJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    def perform(organization:)
      Subscriptions::OrganizationEmittingEventsService.call!(organization:)
    end
  end
end
