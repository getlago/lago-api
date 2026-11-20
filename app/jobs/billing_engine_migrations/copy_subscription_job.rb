# frozen_string_literal: true

module BillingEngineMigrations
  class CopySubscriptionJob < ApplicationJob
    queue_as :low_priority

    unique :until_executed, on_conflict: :log

    def perform(migration, subscription)
      BillingEngineMigrations::CopySubscriptionService.call(migration:, subscription:)
    end
  end
end
