# frozen_string_literal: true

module BillingEngineMigrations
  # Copies V1 events of a migrated organization to its shadow organization, through the product
  # pipeline that only writes to ClickHouse. Product enrichment does not look the contract up, so
  # an event of a subscription that was never copied would be stored and never billed.
  class CopyEventsService < BaseService
    Result = BaseResult[:copied_count, :unmapped_count]

    Event = Data.define(
      :external_customer_id,
      :external_subscription_id,
      :transaction_id,
      :code,
      :timestamp,
      :precise_total_amount_cents,
      :properties
    )

    def initialize(migration:, events:)
      @migration = migration
      @events = events
      super
    end

    def call
      return product_topic_missing_failure if ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"].blank?

      copies = mapped_events

      if copies.any?
        shadow_organization = Organization.find(migration.shadow_organization_id)
        return shadow_organization_store_failure unless shadow_organization.clickhouse_events_store?

        Events::KafkaProducerService.call!(events: copies, organization: shadow_organization, catalog_events: true, sync: true)
      end

      result.copied_count = copies.size
      result.unmapped_count = events.size - copies.size
      result
    end

    private

    attr_reader :migration, :events

    def mapped_events
      mapped_ids = MappedSubscriptions.filter(migration, events.filter_map(&:external_subscription_id))
      events.select { mapped_ids.include?(it.external_subscription_id) }
    end

    def shadow_organization_store_failure
      result.service_failure!(
        code: "shadow_organization_not_on_clickhouse_events_store",
        message: "The shadow organization reads its usage from PostgreSQL, copied events would not reach it"
      )
    end

    def product_topic_missing_failure
      result.service_failure!(
        code: "product_raw_events_topic_missing",
        message: "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC is not set, events cannot be copied to the shadow organization"
      )
    end
  end
end
