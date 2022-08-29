# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class RecurringCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        @from_date = from_date
        @to_date = to_date

        result.aggregation = compute_aggregation.ceil(5)
        result
      end

      private

      attr_reader :from_date, :to_date

      def compute_aggregation
        ActiveRecord::Base.connection
          .execute(aggregation_query)
          .first['aggregation_result']
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period
          persisted.select("SUM(#{persisted_pro_rata}::numeric)").to_sql,

          # NOTE: Added during the period
          added
            .select(
              "SUM(('#{to_date}'::date - DATE(persisted_metrics.added_at) + 1)::numeric / #{period_duration})::numeric",
            )
            .to_sql,

          # NOTE: removed during the period
          removed
            .select(
              "SUM((DATE(persisted_metrics.removed_at) - '#{from_date}'::date + 1)::numeric / #{period_duration})::numeric",
            )
            .to_sql,

          # # NOTE: Added and then removed during the period
          added_and_removed
            .select(
              "SUM((DATE(persisted_metrics.removed_at) - DATE(persisted_metrics.added_at) + 1)::numeric / #{period_duration})::numeric",
            ).to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def base_scope
        PersistedMetric
          .where(customer_id: subscription.customer_id)
          .where(external_subscription_id: subscription.unique_id)
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(subscription, to_date + 1.day)
          .duration_in_days
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        (to_date - from_date + 1).to_i.fdiv(period_duration)
      end

      def persisted
        base_scope
          .where('DATE(persisted_metrics.added_at) < ?', from_date)
          .where('persisted_metrics.removed_at IS NULL OR DATE(persisted_metrics.removed_at) > ?', to_date)
      end

      def added
        base_scope
          .where('DATE(persisted_metrics.added_at) >= ?', from_date)
          .where('DATE(persisted_metrics.added_at) <= ?', to_date)
          .where('persisted_metrics.removed_at IS NULL OR DATE(persisted_metrics.removed_at) > ?', to_date)
      end

      def removed
        base_scope
          .where('DATE(persisted_metrics.added_at) < ?', from_date)
          .where('DATE(persisted_metrics.removed_at) >= ?', from_date)
          .where('DATE(persisted_metrics.removed_at) <= ?', to_date)
      end

      def added_and_removed
        base_scope
          .where('DATE(persisted_metrics.added_at) >= ?', from_date)
          .where('DATE(persisted_metrics.added_at) <= ?', to_date)
          .where('DATE(persisted_metrics.removed_at) >= ?', from_date)
          .where('DATE(persisted_metrics.removed_at) <= ?', to_date)
      end
    end
  end
end
