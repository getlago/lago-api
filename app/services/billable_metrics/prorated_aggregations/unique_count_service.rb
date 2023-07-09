# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class UniqueCountService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        @base_aggregator = BillableMetrics::Aggregations::UniqueCountService.new(**args)

        super(**args)
      end

      def aggregate(from_datetime:, to_datetime:, options: {})
        @from_datetime = from_datetime
        @to_datetime = to_datetime
        @options = options

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_prorated_aggregation.ceil(5)

        if options[:is_current_usage]
          handle_current_usage(aggregation, options[:is_pay_in_advance])
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.options = options
        result.count = result.aggregation
        result
      end

      private

      attr_reader :from_datetime, :to_datetime, :options

      def compute_prorated_aggregation
        ActiveRecord::Base.connection.execute(prorated_aggregation_query).first['aggregation_result']
      end

      def prorated_aggregation_query
        queries = [
          # NOTE: Billed on the full period. We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          prorated_persisted_query.select("SUM(#{persisted_pro_rata}::numeric)").to_sql,

          # NOTE: Added during the period, We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          prorated_added_query.select(duration_ratio_sql('quantified_events.added_at', to_datetime)).to_sql,

          # NOTE: removed during the period
          prorated_removed_query.select(duration_ratio_sql(from_datetime, 'quantified_events.removed_at')).to_sql,

          # NOTE: Added and then removed during the period
          prorated_added_and_removed_query.select(
            duration_ratio_sql(
              'quantified_events.added_at',
              'quantified_events.removed_at',
            ),
          ).to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(
          subscription,
          to_datetime + 1.day,
          current_usage: subscription.terminated? && subscription.upgraded?,
        ).charges_duration_in_days
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        ((to_datetime.to_time - from_datetime.to_time) / 1.day).ceil.fdiv(period_duration)
      end

      def prorated_persisted_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at IS NULL OR quantified_events.removed_at::timestamp(0) > ?', to_datetime)
      end

      def prorated_added_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) IS NULL OR quantified_events.removed_at > ?', to_datetime)
      end

      def prorated_removed_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime)
      end

      def prorated_added_and_removed_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime)
      end

      def base_scope
        quantified_events = QuantifiedEvent
          .joins(customer: :organization)
          .where(billable_metric_id: billable_metric.id)
          .where(customer_id: subscription.customer_id)
          .where(external_subscription_id: subscription.external_id)

        return quantified_events unless group

        group_scope(quantified_events)
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "SUM((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}) + 1)::numeric / #{period_duration})::numeric"
      end
    end
  end
end
