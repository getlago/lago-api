# frozen_string_literal: true

module Events
  module Stores
    class Provider
      def initialize(organization:, billing_context:, usage_buckets: nil, current_usage: false)
        @organization = organization
        @billing_context = billing_context
        @usage_buckets = usage_buckets
        @current_usage = current_usage
      end

      attr_reader :billing_context, :usage_buckets

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

      def precomputed_options_for(charge:, boundaries:, filters: {})
        return {} unless served_from_buckets?(charge:, boundaries:, filters:)

        charge_id = charge.id
        charge_filter_id = bucket_charge_filter_id(filters[:charge_filter])

        {
          precomputed_aggregation: usage_buckets.aggregation_result_for(charge_id:, charge_filter_id:),
          precomputed_grouped_aggregations: usage_buckets.grouped_aggregation_results_for(charge_id:, charge_filter_id:)
        }
      end

      def served_from_buckets?(charge:, boundaries:, filters: {})
        return false unless current_usage
        return false unless RealtimeUsage.enabled?(organization)
        return false if usage_buckets.blank?
        return false if boundaries[:max_timestamp].present?
        return false if RealtimeUsage.deduplicated?(organization)
        return false unless RealtimeUsage.supported_charge?(charge)

        filters[:grouped_by_values].blank? &&
          filters[:event].blank? &&
          filters[:presentation_by].blank? &&
          filters[:filter_by_group].blank?
      end

      private

      attr_reader :organization, :current_usage

      # The sink writes `COALESCE(charge_filter_id, '')`, while the unfiltered fee carries
      # an unpersisted ChargeFilter whose id is nil.
      def bucket_charge_filter_id(charge_filter)
        charge_filter&.id || ""
      end
    end
  end
end
