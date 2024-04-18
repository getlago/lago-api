# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CustomService < BillableMetrics::Aggregations::BaseService
      INITIAL_STATE = { total_units: BigDecimal('0'), amount: BigDecimal('0') }.freeze
      BATCH_SIZE = 1000

      def compute_aggregation(options: {})
        result.count = event_store.count

        aggregation_result = perform_custom_aggregation

        result.aggregation = aggregation_result[:total_units]
        result.custom_aggregation = aggregation_result
        result.options = options
        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
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
        # TODO: fecth state from the cached aggregation
        INITIAL_STATE
      end

      def perform_custom_aggregation
        total_batches = (result.count.to_f / BATCH_SIZE).ceil
        state = current_state

        # NOTE: Loop over events by batch
        (1..total_batches).each do |batch|
          events_properties = event_store.events.page(batch).per(BATCH_SIZE)
            .map { |event| { timestamp: event.timestamp, properties: event.properties } }

          sandboxed_result = LagoUtils::RubySandbox.run(aggregator(events_properties, state))

          state = {
            total_units: BigDecimal(sandboxed_result['total_units'].to_s),
            amount: BigDecimal(sandboxed_result['amount']),
          }
        end

        state
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
        return BigDecimal(0) unless event

        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values,
        )

        unless cached_aggregation
          # TODO(custom_agg): Implement custom aggregation logic
        end

        # TODO(custom_agg): Implement custom aggregation logic
        BigDecimal(0)
      end
    end
  end
end
