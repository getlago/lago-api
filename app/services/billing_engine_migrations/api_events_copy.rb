# frozen_string_literal: true

module BillingEngineMigrations
  # Called on every API event request, so it is not a service: organizations without a migration
  # cost an in-memory lookup and no tracing span. The V1 event is already stored and produced when
  # the copy is enqueued, so an unavailable Redis or database is logged instead of raised.
  module ApiEventsCopy
    UNAVAILABLE_ERRORS = [
      ::Redis::BaseError,
      ::RedisClient::Error,
      ::ConnectionPool::Error,
      ::ConnectionPool::TimeoutError,
      ::ActiveRecord::ActiveRecordError
    ].freeze

    class << self
      def enqueue(organization:, events:)
        return unless copying_api_events?(organization)

        events_attributes = Array.wrap(events).filter_map { attributes_of(it) if it.external_subscription_id.present? }
        CopyApiEventsJob.perform_later(organization.id, events_attributes.to_json) if events_attributes.any?
      rescue *UNAVAILABLE_ERRORS => e
        Rails.logger.error("[billing_engine_migrations] api events copy not enqueued organization_id=#{organization.id}: #{e.class} #{e.message}")
      end

      private

      def copying_api_events?(organization)
        Lookup.for_source(organization.id)&.events_copy_source == BillingEngineMigration::EVENTS_COPY_SOURCES[:api]
      end

      def attributes_of(event)
        {
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          transaction_id: event.transaction_id,
          code: event.code,
          timestamp: event.timestamp.to_f,
          precise_total_amount_cents: event.precise_total_amount_cents&.to_s,
          properties: event.properties
        }
      end
    end
  end
end
