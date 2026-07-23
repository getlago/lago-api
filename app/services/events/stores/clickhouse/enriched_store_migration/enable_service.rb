# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        # Final step of the enriched store migration. Once every subscription migration
        # has reached `completed`, this service enables the feature flag and
        # `pre_filter_events` on the organization, then marks the org migration complete.
        class EnableService < BaseService
          Result = BaseResult[:enriched_store_migration]

          def initialize(enriched_store_migration:)
            @enriched_store_migration = enriched_store_migration
            super
          end

          def call
            return result unless enriched_store_migration.enabling?

            unless enriched_store_migration.all_subscriptions_completed?
              fail_migration!("Cannot enable: not all subscription migrations are completed")
              return result
            end

            ActiveRecord::Base.transaction do
              organization.pre_filter_events = true
              organization.enable_feature_flag!(:enriched_events_aggregation)
              enriched_store_migration.mark_as_completed!
            end

            result.enriched_store_migration = enriched_store_migration
            result
          rescue => e
            fail_migration!(e.message)
            result
          end

          private

          attr_reader :enriched_store_migration

          delegate :organization, to: :enriched_store_migration

          def fail_migration!(message)
            enriched_store_migration.update!(error_message: message)
            enriched_store_migration.fail!
          end
        end
      end
    end
  end
end
