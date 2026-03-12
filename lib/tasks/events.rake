# frozen_string_literal: true

namespace :events do
  # NOTE: related to https://github.com/getlago/lago-api/issues/317
  desc "Fill missing timestamps for events"
  task fill_timestamp: :environment do
    Event.unscoped.where(timestamp: nil).find_each do |event|
      event.update!(timestamp: event.created_at)
    end
  end

  desc "Fill missing subscription_id"
  task fill_subscription: :environment do
    Event.unscoped.where(subscription_id: nil).find_each do |event|
      subscription = event.customer.active_subscription || event.customer.subscriptions.order(:created_at).last

      unless subscription
        event.destroy
        next
      end

      event.update!(subscription_id: subscription.id)
    end
  end

  desc "Deduplicate events_enriched_expanded by removing older versions of duplicate rows"
  task deduplicate_enriched_expanded: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    subscription_ids = ENV["SUBSCRIPTION_IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
    codes = ENV["BM_CODES"].to_s.split(",").map(&:strip).reject(&:blank?)
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    organization = Organization.find(organization_id)
    subscriptions = organization.subscriptions
    subscriptions = subscriptions.where(id: subscription_ids) if subscription_ids.present?

    total_duplicates = 0

    subscriptions.find_each do |subscription|
      service = Events::Stores::Clickhouse::CleanDuplicatedEnrichedExpandedService.new(subscription:, codes:)

      duplicate_count = service.count_duplicates

      if dry_run
        Rails.logger.info(
          "events:deduplicate_enriched_expanded [DRY RUN] - Subscription #{subscription.external_id}: #{duplicate_count} duplicate rows would be removed"
        )
      else
        result = service.call
        duplicate_count = result.removed_count

        Rails.logger.info(
          "events:deduplicate_enriched_expanded - Subscription #{subscription.external_id}: #{duplicate_count} duplicate rows removed"
        )
      end

      total_duplicates += duplicate_count
    end

    mode = dry_run ? "DRY RUN" : "LIVE"
    action = dry_run ? "found" : "removed"
    Rails.logger.info("events:deduplicate_enriched_expanded [#{mode}] - Complete. #{total_duplicates} total duplicate rows #{action}.")
  end

  desc "Reprocess events by pushing them back to events_raw Kafka topic with reprocess flag"
  task reprocess: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    subscription_ids = ENV["SUBSCRIPTION_IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
    codes = ENV["BM_CODES"].to_s.split(",").map(&:strip).reject(&:blank?)
    reprocess = ENV.fetch("REPROCESS", "true") == "true"
    batch_size = (ENV["BATCH_SIZE"] || 1000).to_i
    sleep_seconds = (ENV["SLEEP_SECONDS"] || 0.5).to_f
    organization = Organization.find(organization_id)
    subscriptions = organization.subscriptions
    subscriptions = subscriptions.where(id: subscription_ids) if subscription_ids.present?

    total = 0
    total_batches = 0

    subscriptions.find_each do |subscription|
      Rails.logger.info("events:reprocess - Processing subscription #{subscription.external_id} (started_at: #{subscription.started_at})")

      service_result = Events::Stores::Clickhouse::ReEnrichEventsService.call(
        subscription:, codes:, reprocess:, batch_size:, sleep_seconds:
      )

      total += service_result.events_count
      total_batches += service_result.batch_count

      Rails.logger.info("events:reprocess - Subscription #{subscription.external_id}: #{service_result.events_count} events in #{service_result.batch_count} batches")
    end

    Rails.logger.info("events:reprocess - Complete. #{total} events reprocessed in #{total_batches} batches.")
  ensure
    # Close the producer to flush pending messages and release resources.
    Karafka.producer.close
  end
end
