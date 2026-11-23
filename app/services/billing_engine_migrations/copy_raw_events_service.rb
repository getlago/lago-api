# frozen_string_literal: true

module BillingEngineMigrations
  # The raw events topic carries the events of every organization, so a payload is parsed only
  # when it contains the id of a migrated organization.
  class CopyRawEventsService < BaseService
    Result = BaseResult[:copied_count, :unmapped_count, :invalid_count]

    RawEvent = Data.define(
      :external_customer_id,
      :external_subscription_id,
      :transaction_id,
      :code,
      :timestamp,
      :precise_total_amount_cents,
      :properties
    )

    NUMERIC_TIMESTAMP = /\A\d+(\.\d+)?\z/

    def initialize(migrations:, raw_payloads:)
      @migrations = migrations
      @raw_payloads = raw_payloads
      super
    end

    def call
      return product_topic_missing_failure if ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"].blank?

      result.copied_count = 0
      result.unmapped_count = 0
      result.invalid_count = 0

      migrations.each { copy_events_of(it) }
      result
    end

    private

    attr_reader :migrations, :raw_payloads

    def copy_events_of(migration)
      events = raw_payloads
        .select { it&.include?(migration.organization_id) }
        .filter_map { build_event(it, migration) }
      return if events.empty?

      mapped_ids = MappedSubscriptions.filter(migration, events.filter_map(&:external_subscription_id))
      copies = events.select { mapped_ids.include?(it.external_subscription_id) }
      produce(migration, copies) if copies.any?

      result.copied_count += copies.size
      result.unmapped_count += events.size - copies.size
    end

    def build_event(raw_payload, migration)
      payload = parse(raw_payload)
      return count_invalid if payload.nil?
      return unless payload["organization_id"] == migration.organization_id

      timestamp = parse_timestamp(payload["timestamp"])
      return count_invalid if timestamp.nil? || payload["transaction_id"].blank? || payload["code"].blank?

      RawEvent.new(
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

    def parse_timestamp(value)
      case value
      when Numeric then Time.zone.at(value)
      when NUMERIC_TIMESTAMP then Time.zone.at(Float(value))
      when String then Time.zone.iso8601(value)
      end
    rescue ArgumentError
      nil
    end

    def produce(migration, events)
      Events::KafkaProducerService.call!(
        events:,
        organization: Organization.find(migration.shadow_organization_id),
        catalog_events: true,
        sync: true
      )
    end

    def count_invalid
      result.invalid_count += 1
      nil
    end

    def product_topic_missing_failure
      result.service_failure!(
        code: "product_raw_events_topic_missing",
        message: "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC is not set, events cannot be copied to the shadow organization"
      )
    end
  end
end
