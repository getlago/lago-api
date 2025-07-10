# frozen_string_literal: true

module FixedCharges
  module FixedChargesEvents
    class ProratedAggregationService < BaseAggregationService
      Result = BaseResult[
        :aggregation, # Total units from events (prorated)
        :current_usage_units, # Units for current usage
        :full_units_number, # Total units ignoring proration
        :count, # Number of events
        :total_aggregated_units, # Total aggregated units
        :full_period_days # Number of days in the period
      ]

      def call
        full_units = fixed_charge_events.last.units
        result.full_units_number = full_units
        result.current_usage_units = full_units
        result.count = fixed_charge_events.count
        result.total_aggregated_units = full_units
        result.full_period_days = charges_duration

        if fixed_charge.prorated?
          # For prorated fixed charges, calculate the prorated units
          # based on the subscription period vs full billing period
          result.aggregation = calculate_proration.ceil(5)
        else
          # For non-prorated fixed charges, use the full units
          result.aggregation = full_units
        end

        result
      end

      private

      attr_reader :fixed_charge, :subscription, :boundaries

      delegate :plan, to: :fixed_charge

      def calculate_proration
        sql_template = <<-SQL
          WITH events_data AS (
            SELECT
              timestamp,
              (#{sanitized_property_name})::numeric AS units,
              #{duration_days_sql} AS duration_days
            FROM fixed_charge_events
            ORDER BY timestamp ASC
          )
          SELECT COALESCE(SUM(units * period_ratio), 0) as aggregation
          FROM (
            SELECT (
              CASE WHEN units > 0
              THEN
                duration_days / #{charges_duration}::numeric
              ELSE
                0 -- NOTE: no units, so no contribution
              END
            ) AS period_ratio
            , units
            FROM events_data
          ) cumulated_ratios
        SQL

        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sql_template,
            {
              from_datetime: from_datetime,
              to_datetime: to_datetime,
              timezone: customer.applicable_timezone
            }
          ]
        )

        ActiveRecord::Base.connection.execute(sql).first["aggregation"]
      end

      private

      def duration_days_sql
        <<-SQL
          -- NOTE: duration in days between current event and next one - using end of period as final boundaries
          (
            (
              DATE((
                -- NOTE: if following event is older than the start of the period, we use the start of the period as the reference
                CASE WHEN (LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp)) < :from_datetime
                THEN :from_datetime
                ELSE LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp) + interval '1' day
                END
              )::timestamptz AT TIME ZONE :timezone)
              - DATE((
                -- NOTE: if events is older than the start of the period, we use the start of the period as the reference
                CASE WHEN timestamp < :from_datetime THEN :from_datetime ELSE timestamp END
              )::timestamptz AT TIME ZONE :timezone)
            )::numeric
          )
        SQL
      end

      def sanitized_property_name
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ["fixed_charge_events.properties->>?", "units"]
        )
      end

      # I don't think it's responsibility of the aggregation service... because
      # we can aggregate over any period, and these are from the billing service...
      # looking at fees/charge_service.rb, the boundaries should include charge_duration.
      # def full_period_days
      #   # Calculate the real number of days in the billing period
      #   # based on the subscription's billing cycle
      #   case plan.interval
      #   when "monthly"
      #     # Calculate days from the start of the billing period to the start of the next billing period
      #     billing_start = subscription.started_at.beginning_of_month.to_date
      #     billing_end = billing_start.next_month.to_date
      #     (billing_end - billing_start).to_i
      #   when "yearly"
      #     # Calculate days from the start of the billing period to the start of the next billing period
      #     billing_start = subscription.started_at.beginning_of_year.to_date
      #     billing_end = billing_start.next_year.to_date
      #     (billing_end - billing_start).to_i
      #   when "weekly"
      #     7 # a week always has 7 days
      #   when "quarterly"
      #     # Calculate days from the start of the billing period to the start of the next billing period
      #     billing_start = subscription.started_at.beginning_of_quarter.to_date
      #     billing_end = billing_start.next_quarter.to_date
      #     (billing_end - billing_start).to_i
      #   else
      #     raise "Unsupported interval: #{plan.interval}"
      #   end
      # end
    end
  end
end
