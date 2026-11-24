# frozen_string_literal: true

module BillingEngineMigrations
  class CopyApiEventsJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_EVENTS"])
        :events
      else
        :default
      end
    end

    # A resent copy keeps its transaction id and timestamp, so the product events table replaces it.
    retry_on WaterDrop::Errors::ProduceError, wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::QueryAborted, wait: :polynomially_longer, attempts: 5

    def perform(organization_id, events_json)
      BillingEngineMigrations::CopyApiEventsService.call!(organization_id:, events_json:)
    end
  end
end
