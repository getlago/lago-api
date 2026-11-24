# frozen_string_literal: true

module BillingEngineMigrations
  # The raw events topic carries the events of every organization, so a payload is parsed only
  # when it contains the id of a migrated organization. Re-enrichment replays are skipped: they
  # re-send a subscription's events since it started, which would reach the shadow organization
  # for the re-enriched subscriptions only.
  class CopyRawEventsService < BaseService
    Result = BaseResult[:copied_count, :unmapped_count, :invalid_count, :replayed_count]

    NUMERIC_TIMESTAMP = /\A\d+(\.\d+)?\z/

    def initialize(migrations:, raw_payloads:)
      @migrations = migrations
      @raw_payloads = raw_payloads
      super
    end

    def call
      result.copied_count = 0
      result.unmapped_count = 0
      result.invalid_count = 0
      result.replayed_count = 0

      migrations.each do |migration|
        break if result.failure?

        copy_events_of(migration)
      end
      result
    end

    private

    attr_reader :migrations, :raw_payloads

    def copy_events_of(migration)
      events = raw_payloads
        .select { it&.include?(migration.organization_id) }
        .filter_map { build_event(it, migration) }
      return if events.empty?

      copy_result = CopyEventsService.call(migration:, events:)
      return result.fail_with_error!(copy_result.error) if copy_result.failure?

      result.copied_count += copy_result.copied_count
      result.unmapped_count += copy_result.unmapped_count
    end

    def build_event(raw_payload, migration)
      payload = parse(raw_payload)
      return count_invalid if payload.nil?
      return unless payload["organization_id"] == migration.organization_id
      return count_replayed if replay?(payload)

      timestamp = parse_timestamp(payload["timestamp"])
      return count_invalid if timestamp.nil? || payload["transaction_id"].blank? || payload["code"].blank?

      CopyEventsService::Event.new(
        external_customer_id: payload["external_customer_id"],
        external_subscription_id: payload["external_subscription_id"],
        transaction_id: payload["transaction_id"],
        code: payload["code"],
        timestamp:,
        precise_total_amount_cents: payload["precise_total_amount_cents"],
        properties: payload["properties"] || {}
      )
    end

    def parse(raw_payload)
      payload = JSON.parse(raw_payload)
      payload if payload.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def replay?(payload)
      source_metadata = payload["source_metadata"]
      source_metadata.is_a?(Hash) && source_metadata["reprocess"] == true
    end

    def parse_timestamp(value)
      case value
      when Numeric then Time.zone.at(value)
      when NUMERIC_TIMESTAMP then Time.zone.at(Float(value))
      when String then Time.zone.iso8601(value)
      end
    rescue ArgumentError
      nil
    end

    def count_invalid
      result.invalid_count += 1
      nil
    end

    def count_replayed
      result.replayed_count += 1
      nil
    end
  end
end
