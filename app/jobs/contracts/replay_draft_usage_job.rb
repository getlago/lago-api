# frozen_string_literal: true

module Contracts
  class ReplayDraftUsageJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_EVENTS"])
        :events
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(contract, published_at)
      Contracts::ReplayDraftUsageService.call!(contract:, published_at:)
    end
  end
end
