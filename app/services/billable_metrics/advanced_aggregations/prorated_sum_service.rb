# frozen_string_literal: true

module BillableMetrics
  module AdvancedAggregations
    class ProratedSumService < BillableMetrics::Aggregations::SumService
      def aggregate(from_datetime:, to_datetime:, options: {})
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        # For charges that are pay in advance on billing date we always bill full amount
        return super if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_aggregation.ceil(5)

        if options[:is_current_usage]
          result_without_proration = super
          handle_current_usage(result_without_proration, aggregation, options[:is_pay_in_advance])
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = events.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      def compute_pay_in_advance_aggregation
        return BigDecimal(0) unless event
        return BigDecimal(0) if event.properties.blank?

        result_without_proration = super

        number_of_days = to_datetime.in_time_zone(customer.applicable_timezone) -
                         event.timestamp.in_time_zone(customer.applicable_timezone)
        proration_coefficient = number_of_days.fdiv(86_400).round.fdiv(period_duration)

        value = (result_without_proration * proration_coefficient).ceil(5)

        extend_event_metadata(value)

        value
      end

      private

      attr_reader :from_datetime, :to_datetime

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
        @persisted_query ||= begin
          query = recurring_events_scope(to_datetime: from_datetime)
          query.where("#{sanitized_field_name} IS NOT NULL")
        end
      end

      def period_query
        @period_query ||= begin
          query = recurring_events_scope(to_datetime:, from_datetime:)
          query.where("#{sanitized_field_name} IS NOT NULL")
        end
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        ((to_datetime.to_time - from_datetime.to_time) / 1.day).ceil.fdiv(period_duration)
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(
          subscription,
          to_datetime + 1.day,
          current_usage: subscription.terminated? && subscription.upgraded?,
        ).charges_duration_in_days

        @period_duration
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}))::numeric + 1) / #{period_duration}::numeric"
      end

      def extend_event_metadata(prorated_value)
        unless previous_event
          result.max_aggregation_with_proration = prorated_value.to_s

          return
        end

        if BigDecimal(result.max_aggregation) > BigDecimal(previous_event.metadata['max_aggregation'])
          result.max_aggregation_with_proration =
            (BigDecimal(previous_event.metadata['max_aggregation_with_proration']) + prorated_value).to_s
        else
          result.max_aggregation_with_proration = BigDecimal(previous_event.metadata['max_aggregation_with_proration'])
        end
      end

      def handle_current_usage(result_without_proration, result_with_proration, is_pay_in_advance)
        value_without_proration = result_without_proration.aggregation

        if !is_pay_in_advance
          result.aggregation = result_with_proration.negative? ? 0 : result_with_proration
          result.current_usage_units = value_without_proration.negative? ? 0 : value_without_proration
        elsif previous_event
          result.current_usage_units = result_without_proration.current_usage_units
          result.aggregation = result_without_proration.current_usage_units -
                               BigDecimal(previous_event.metadata['current_aggregation']) +
                               BigDecimal(previous_event.metadata['max_aggregation_with_proration'])
        else
          result.aggregation = value_without_proration
          result.current_usage_units = result_without_proration.current_usage_units
        end
      end
    end
  end
end
