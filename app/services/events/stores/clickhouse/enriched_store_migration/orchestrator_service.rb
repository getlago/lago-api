# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        # Top-level driver for an organization's enriched store migration.
        # Reads the current org migration state and dispatches the next action. Idempotent.
        #
        #   pending    → transition to checking, enqueue CheckJob
        #   processing → if all subscriptions completed: transition to enabling, enqueue EnableJob
        #                otherwise: no-op (wait for remaining subscription migrations to finish)
        #   other      → no-op
        class OrchestratorService < BaseService
          Result = BaseResult[:enriched_store_migration]

          def initialize(enriched_store_migration:)
            @enriched_store_migration = enriched_store_migration
            super
          end

          def call
            case enriched_store_migration.status
            when "pending"
              handle_pending
            when "processing"
              handle_processing
            else
              Rails.logger.error("Unknown status: #{enriched_store_migration.status}")
            end

            result.enriched_store_migration = enriched_store_migration
            result
          end

          private

          attr_reader :enriched_store_migration

          def handle_pending
            enriched_store_migration.update!(started_at: Time.current) if enriched_store_migration.started_at.nil?
            enriched_store_migration.start_check!
            CheckJob.perform_later(enriched_store_migration)
          end

          def handle_processing
            return unless enriched_store_migration.all_subscriptions_completed?

            enriched_store_migration.start_enabling!
            EnableJob.perform_later(enriched_store_migration)
          end
        end
      end
    end
  end
end
