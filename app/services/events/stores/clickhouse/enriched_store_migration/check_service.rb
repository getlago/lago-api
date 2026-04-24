# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module EnrichedStoreMigration
        # Runs the pre-enrichment check for the organization and creates one
        # EnrichedStoreSubscriptionMigration record per active subscription.
        #
        # Subscriptions flagged by PreEnrichmentCheckService get their required billable
        # metric codes populated. All other active subscriptions get an empty codes array
        # and will skip straight through the comparison fast path.
        #
        # After records are created, transitions the org migration to `processing` and
        # enqueues a SubscriptionOrchestratorJob for each subscription migration.
        class CheckService < BaseService
          BATCH_SIZE = 100

          Result = BaseResult[:enriched_store_migration, :subscription_migration_count]

          def initialize(enriched_store_migration:)
            @enriched_store_migration = enriched_store_migration
            super
          end

          def call
            return result unless enriched_store_migration.checking?

            check_result = ::Events::Stores::Clickhouse::PreEnrichmentCheckService.call(organization:)

            unless check_result.success?
              fail_migration!(check_result.error&.message || "Pre-enrichment check failed")
              return result
            end

            nb_jobs_enqueued = 0

            ActiveRecord::Base.transaction do
              enriched_store_migration.start_processing!

              organization.subscriptions.active.select(:id).in_batches(of: BATCH_SIZE) do |batch|
                jobs = create_subscription_migrations(batch, check_result.subscriptions_to_reprocess)
                after_commit { ActiveJob.perform_all_later(jobs) }

                nb_jobs_enqueued += jobs.size
              end
            end

            result.enriched_store_migration = enriched_store_migration
            result.subscription_migration_count = nb_jobs_enqueued
            result
          rescue => e
            fail_migration!(e.message)
            result
          end

          private

          attr_reader :enriched_store_migration

          delegate :organization, to: :enriched_store_migration

          def create_subscription_migrations(batch, subscriptions_to_reprocess)
            batch.each.map do |subscription|
              codes = subscriptions_to_reprocess[subscription.id] || []

              migration = EnrichedStoreSubscriptionMigration.create!(
                enriched_store_migration:,
                organization:,
                subscription_id: subscription.id,
                billable_metric_codes: codes,
                started_at: Time.current
              )

              SubscriptionOrchestratorJob.new(migration)
            end
          end

          def fail_migration!(message)
            enriched_store_migration.update!(error_message: message)
            enriched_store_migration.fail!
          end
        end
      end
    end
  end
end
