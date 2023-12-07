# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class SumService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        @base_aggregator = BillableMetrics::Aggregations::SumService.new(**args)

        super(**args)
      end

      def aggregate(options: {})
        @options = options

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_aggregation.ceil(5)
        result.full_units_number = aggregation_without_proration.aggregation if event.nil?

        if options[:is_current_usage]
          handle_current_usage(aggregation, options[:is_pay_in_advance])
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = aggregation_without_proration.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      def compute_per_event_prorated_aggregation
        period_query
          .pluck(
            Arel.sql(
              "(COALESCE((#{sanitized_field_name})::numeric, 0)) * "\
              "(#{duration_ratio_sql('events.timestamp', to_datetime)})::numeric",
            ),
          )
      end

      def per_event_aggregation
        recurring_result = recurring_value
        recurring_aggregation = recurring_result ? [BigDecimal(recurring_result) * persisted_pro_rata] : []

        Result.new.tap do |result|
          result.event_aggregation = recurring_aggregation + base_aggregator.compute_per_event_aggregation
          result.event_prorated_aggregation = recurring_aggregation + compute_per_event_prorated_aggregation
        end
      end

      protected

      def compute_aggregation
        ActiveRecord::Base.connection.execute(aggregation_query).first['aggregation_result']
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period
          persisted_query
            .select("SUM((CAST(#{sanitized_field_name} AS FLOAT)) * (#{persisted_pro_rata}))::numeric")
            .to_sql,

          # NOTE: Added during the period
          period_query
            .select("SUM((CAST(#{sanitized_field_name} AS FLOAT)) * "\
                    "(#{duration_ratio_sql('events.timestamp', to_datetime)}))::numeric")
            .to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def persisted_query
        @persisted_query ||= recurring_events_scope(to_datetime: from_datetime)
          .where(field_presence_condition)
          .where(field_numeric_condition)
      end

      def period_query
        @period_query ||= recurring_events_scope(to_datetime:, from_datetime:)
          .where(field_presence_condition)
          .where(field_numeric_condition)
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}))::numeric + 1) / #{period_duration}::numeric"
      end

      def recurring_value
        previous_charge_fee_units = previous_charge_fee&.units
        return previous_charge_fee_units if previous_charge_fee_units

        query = persisted_query
          .select("SUM(((#{sanitized_field_name})::numeric) * (#{persisted_pro_rata}))::numeric").to_sql
        recurring_value_before_first_fee = ActiveRecord::Base.connection.select_one(query)['sum']

        ((recurring_value_before_first_fee || 0) <= 0) ? nil : recurring_value_before_first_fee
      end
    end
  end
end
