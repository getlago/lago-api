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
  task deduplicate: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    subscription_ids = ENV["SUBSCRIPTION_IDS"]&.split(",")&.map(&:strip)&.reject(&:blank?)
    codes = ENV["BM_CODES"]&.split(",")&.map(&:strip)&.reject(&:blank?)
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    organization = Organization.find(organization_id)
    subscriptions = organization.subscriptions
    subscriptions = subscriptions.where(id: subscription_ids) if subscription_ids.present?

    total_duplicates = 0

    subscriptions.find_each do |subscription|
      started_at = subscription.started_at.strftime("%Y-%m-%d %H:%M:%S")
      sub_id = subscription.id

      code_condition = if codes.present?
        code_list = codes.map { |c| "'#{ActiveRecord::Base.sanitize_sql_like(c)}'" }.join(", ")
        "AND code IN (#{code_list})"
      else
        ""
      end

      where_clause = <<~SQL.squish
        organization_id = '#{organization.id}'
        AND subscription_id = '#{sub_id}'
        AND timestamp >= '#{started_at}'
        #{code_condition}
      SQL

      count_sql = <<~SQL.squish
        SELECT count() as cnt
        FROM events_enriched_expanded
        WHERE #{where_clause}
        AND (organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp, enriched_at)
        NOT IN (
          SELECT
            organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp,
            max(enriched_at) as enriched_at
          FROM events_enriched_expanded
          WHERE #{where_clause}
          GROUP BY organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp
        )
      SQL

      result = Clickhouse::EventsEnrichedExpanded.connection.select_one(count_sql)
      duplicate_count = result["cnt"].to_i

      if dry_run
        Rails.logger.info(
          "events:deduplicate [DRY RUN] - Subscription #{subscription.external_id}: #{duplicate_count} duplicate rows would be removed"
        )
      else
        if duplicate_count > 0
          delete_sql = <<~SQL.squish
            ALTER TABLE events_enriched_expanded
            DELETE WHERE #{where_clause}
            AND (organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp, enriched_at)
            NOT IN (
              SELECT
                organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp,
                max(enriched_at) as enriched_at
              FROM events_enriched_expanded
              WHERE #{where_clause}
              GROUP BY organization_id, subscription_id, charge_id, charge_filter_id, transaction_id, timestamp
            )
          SQL

          Clickhouse::EventsEnrichedExpanded.connection.execute(delete_sql)
        end

        Rails.logger.info(
          "events:deduplicate - Subscription #{subscription.external_id}: #{duplicate_count} duplicate rows removed"
        )
      end

      total_duplicates += duplicate_count
    end

    mode = dry_run ? "DRY RUN" : "LIVE"
    action = dry_run ? "found" : "removed"
    Rails.logger.info("events:deduplicate [#{mode}] - Complete. #{total_duplicates} total duplicate rows #{action}.")
  end

  desc "Reprocess events by pushing them back to events_raw Kafka topic with reprocess flag"
  task reprocess: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    subscription_ids = ENV["SUBSCRIPTION_IDS"]&.split(",")&.map(&:strip).reject(&:blank?)
    codes = ENV["BM_CODES"]&.split(",")&.map(&:strip).reject(&:blank?)
    reprocess = ENV.fetch("REPROCESS", "true") == "true"
    batch_size = (ENV["BATCH_SIZE"] || 1000).to_i
    sleep_seconds = (ENV["SLEEP_SECONDS"] || 0.5).to_f
    topic = ENV.fetch("LAGO_KAFKA_RAW_EVENTS_TOPIC")

    organization = Organization.find(organization_id)
    subscriptions = organization.subscriptions
    subscriptions = subscriptions.where(id: subscription_ids) if subscription_ids.present?

    total = 0
    batch_count = 0

    subscriptions.find_each do |subscription|
      scope = Clickhouse::EventsRaw
        .where(organization_id:, external_subscription_id: subscription.external_id)
        .where("timestamp >= ?", subscription.started_at)
      scope = scope.where(code: codes) if codes.present?

      Rails.logger.info("events:reprocess - Processing subscription #{subscription.external_id} (started_at: #{subscription.started_at})")

      scope.order(:timestamp).in_batches(of: batch_size) do |batch|
        events = batch.to_a
        messages = events.map do |event|
          properties = event.properties
          properties = JSON.parse(properties) if properties.is_a?(String)

          payload = {
            organization_id: event.organization_id,
            external_customer_id: event.external_customer_id,
            external_subscription_id: event.external_subscription_id,
            transaction_id: event.transaction_id,
            timestamp: event.timestamp.to_f.to_s,
            code: event.code,
            precise_total_amount_cents: event.precise_total_amount_cents.present? ? event.precise_total_amount_cents.to_s : "0.0",
            properties:,
            ingested_at: Time.zone.now.iso8601[...-1],
            source: Events::KafkaProducerService::EVENT_SOURCE,
            source_metadata: {
              api_post_processed: true,
              reprocess:
            }
          }

          {
            topic:,
            key: "#{event.organization_id}-#{event.external_subscription_id}",
            payload: payload.to_json
          }
        end

        Karafka.producer.produce_many_async(messages)

        batch_count += 1
        total += events.size
        Rails.logger.info("events:reprocess - Batch ##{batch_count}: #{events.size} events (total: #{total})")

        sleep(sleep_seconds)
      end
    end

    Rails.logger.info("events:reprocess - Complete. #{total} events reprocessed in #{batch_count} batches.")
  ensure
    # Close the producer to flush pending messages and release resources.
    Karafka.producer.close
  end
end
