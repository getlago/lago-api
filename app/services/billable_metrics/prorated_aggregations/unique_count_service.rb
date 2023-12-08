# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class UniqueCountService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        @base_aggregator = BillableMetrics::Aggregations::UniqueCountService.new(**args)

        super(**args)
      end

      def aggregate(options: {})
        @options = options

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_prorated_aggregation.ceil(5)
        result.full_units_number = aggregation_without_proration.aggregation if event.nil?

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

      def per_event_aggregation
        recurring_result = recurring_value
        recurring_aggregation = recurring_result ? [BigDecimal(recurring_result)] : []
        recurring_prorated_aggregation = recurring_result ? [BigDecimal(recurring_result) * persisted_pro_rata] : []
        period_agg = compute_per_event_prorated_aggregation

        Result.new.tap do |result|
          result.event_aggregation = recurring_aggregation + (0...period_agg.count).map { |_| 1 }
          result.event_prorated_aggregation = recurring_prorated_aggregation + period_agg
        end
      end

      protected

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
          .where(billable_metric_id: billable_metric.id)
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)

        return quantified_events unless group

        count_unique_group_scope(quantified_events)
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "SUM((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}) + 1)::numeric / #{period_duration})::numeric"
      end

      def compute_per_event_prorated_aggregation
        all_events = added_list + removed_list + added_and_removed_list

        all_events = all_events.sort_by(&:time)

        all_events.pluck(:value)
      end

      def added_list
        time_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')

        added_elements = prorated_added_query.group(Arel.sql("#{time_field}, quantified_events.id"))
          .order(Arel.sql("#{time_field} ASC"))
          .pluck(
            Arel.sql(
              [
                "(#{duration_ratio_sql('quantified_events.added_at', to_datetime)})::numeric",
                time_field,
              ].join(', '),
            ),
          )

        added_elements.map do |element|
          OpenStruct.new(
            time: element.last,
            value: element.first,
          )
        end
      end

      def removed_list
        time_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        removed_elements = prorated_removed_query.group(Arel.sql("#{time_field}, quantified_events.id"))
          .order(Arel.sql("#{time_field} ASC"))
          .pluck(
            Arel.sql(
              [
                "(#{duration_ratio_sql(from_datetime, 'quantified_events.removed_at')})::numeric",
                time_field,
              ].join(', '),
            ),
          )

        removed_elements.map do |element|
          OpenStruct.new(
            time: element.last,
            value: element.first,
          )
        end
      end

      def added_and_removed_list
        added_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')
        removed_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        added_and_removed_elements = prorated_added_and_removed_query.group(
          Arel.sql("#{added_field}, #{removed_field}, quantified_events.id"),
        ).order(
          Arel.sql("#{added_field} ASC, #{removed_field} ASC"),
        ).pluck(Arel.sql(
          [
            "(#{duration_ratio_sql('quantified_events.added_at', 'quantified_events.removed_at')})::numeric",
            added_field,
          ].join(', '),
        ))

        added_and_removed_elements.map do |element|
          OpenStruct.new(
            time: element.last,
            value: element.first,
          )
        end
      end

      def recurring_value
        previous_charge_fee_units = previous_charge_fee&.units
        return previous_charge_fee_units if previous_charge_fee_units

        recurring_value_before_first_fee = prorated_persisted_query.sum('1::numeric')

        (recurring_value_before_first_fee <= 0) ? nil : recurring_value_before_first_fee
      end
    end
  end
end
