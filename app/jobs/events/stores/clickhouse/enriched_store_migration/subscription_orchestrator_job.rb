# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        class SubscriptionOrchestratorJob < ApplicationJob
          queue_as "low_priority"

          def perform(subscription_migration)
            SubscriptionOrchestratorService.call!(subscription_migration:)
          end
        end
      end
    end
  end
end
