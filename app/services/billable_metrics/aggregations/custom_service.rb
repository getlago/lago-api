# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CustomService < BillableMetrics::Aggregations::BaseService
      INITIAL_STATE = { total_units: BigDecimal('0'), amount: BigDecimal('0') }.freeze
      BATCH_SIZE = 1000

      def compute_aggregation(options: {})
        result.count = event_store.count

        aggregation_result = perform_custom_aggregation
        in_advance_aggregation_result = compute_pay_in_advance_aggregation

        result.aggregation = aggregation_result[:total_units]
        result.current_usage_units = result.aggregation # TODO: Used cached aggregation
        result.custom_aggregation = event ? in_advance_aggregation_result : aggregation_result
        result.options = options
        result.pay_in_advance_aggregation = in_advance_aggregation_result[:total_units]
        result
      end

      def compute_grouped_by_aggregation
        # TODO(custom_agg): Implement custom aggregation logic
        result.aggregations = []
      end

      def compute_per_event_aggregation
        # TODO: Implement custom aggregation logic returning 1 value per event
        event_store.events_properties
      end

      private

      def custom_properties
        charge.properties['custom_properties']
      end

      def current_state
        # TODO: fecth state from the cached aggregation for recurring and current usage
        INITIAL_STATE
      end

      def perform_custom_aggregation
        total_batches = (result.count.to_f / BATCH_SIZE).ceil
        state = current_state

        # NOTE: Loop over events by batch
        (1..total_batches).each do |batch|
          events_properties = event_store.events.page(batch).per(BATCH_SIZE)
            .map { |event| { timestamp: event.timestamp, properties: event.properties } }

          state = sandboxed_aggregation(events_properties, state)
        end

        state
      end

      def sandboxed_aggregation(events_properties, state)
        sandboxed_result = LagoUtils::RubySandbox.run(aggregator(events_properties, state))

        {
          total_units: BigDecimal(sandboxed_result['total_units'].to_s),
          amount: BigDecimal(sandboxed_result['amount'].to_s),
        }
      end

      def aggregator(events_properties, current_state)
        <<~RUBY
          class EventValues
            def initialize(timestamp:, properties:)
              @timestamp = timestamp
              @properties = properties
            end

            attr_reader :timestamp, :properties
          end

          initial_state = {
            total_units: BigDecimal('#{current_state[:total_units]}'),
            amount: BigDecimal('#{current_state[:amount]}')
          }

          aggregation_properties = JSON.parse('#{custom_properties.to_json}')

          #{billable_metric.custom_aggregator}

          events = [
            #{events_properties.map do |event|
              "EventValues.new(timestamp: Time.at(#{event[:timestamp].to_f}),properties: #{event[:properties].as_json})"
            end.join(",\n")}
          ]

          result = events.each_with_object(initial_state.dup) do |event, agg|
            res = aggregate(event, agg, aggregation_properties)

            agg[:total_units] = res[:total_units]
            agg[:amount] += res[:amount]
          end

          result
        RUBY
      end

      def compute_pay_in_advance_aggregation
        return INITIAL_STATE unless event

        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values,
        )

        # NOTE: The aggregation was never performed on the period,
        #       we need to perform a full aggregation and cache it
        unless cached_aggregation
          state = perform_custom_aggregation

          assign_cached_metadata(
            current_aggregation: state[:total_units],
            max_aggregation: state[:total_units],
            units_applied: state[:total_units],
            current_amount: state[:amount],
          )

          return state
        end

        # NOTE: Retrieve values from the previous aggregation
        old_aggregation = cached_aggregation.current_aggregation_decimal
        old_max = cached_aggregation.max_aggregation_decimal
        old_amount = cached_aggregation.current_amount_decimal

        # NOTE: compute aggregation for the current event, using the previous state
        event_aggregation = sandboxed_aggregation(
          [{ timestamp: event.timestamp, properties: event.properties }],
          { total_units: old_aggregation, amount: old_amount },
        )

        units_applied = event_aggregation[:total_units] - old_aggregation
        max_aggregation = if event_aggregation[:total_units] > old_max
          event_aggregation[:total_units]
        else
          old_max
        end

        # NOTE: Update the metadata for the current event
        assign_cached_metadata(
          current_aggregation: event_aggregation[:total_units],
          max_aggregation:,
          units_applied:,
          current_amount: event_aggregation[:amount],
        )

        # NOTE: Return the amount and units to be charged for the current event
        {
          total_units: units_applied,
          amount: event_aggregation[:amount] - old_amount,
        }
      end

      def assign_cached_metadata(current_aggregation:, max_aggregation:, units_applied: nil, current_amount: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
        result.current_amount = current_amount unless current_amount.nil?
      end
    end
  end
end
