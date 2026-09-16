# frozen_string_literal: true

module Events
  module Stores
    class Provider
      def initialize(organization:, billing_context:)
        @organization = organization
        @billing_context = billing_context
      end

      attr_reader :billing_context

      def store_for(metered_item:, boundaries:, filters: {})
        store_class.new(
          code: metered_item.billable_metric.code,
          billing_context:,
          boundaries:,
          filters:,
          deduplicate:
        )
      end

      def store_class
        @store_class ||= Events::Stores::StoreFactory.store_class(organization:)
      end

      def deduplicate
        return @deduplicate if defined?(@deduplicate)

        override = Events::Stores::StoreFactory.override
        @deduplicate = if override
          override[:deduplicate]
        else
          organization.clickhouse_events_store? && organization.clickhouse_deduplication_enabled?
        end
      end

      private

      attr_reader :organization
    end
  end
end
