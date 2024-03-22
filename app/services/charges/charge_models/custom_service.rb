# frozen_string_literal: true

module Charges
  module ChargeModels
    class CustomService < Charges::ChargeModels::BaseService
      protected

      INITIAL_STATE = { total_units: BigDecimal('0'), amount: BigDecimal('0') }.freeze

      def compute_amount
        # TODO: fetch cached result to reinject it into the aggregation result as a "previous state"
        # NOTE: cached result should take the timestamp into account to allow recompute from a specific datetime

        # NOTE: load the custom aggregation logic
        instance_eval(custom_aggregator)

        aggregation = aggregator.per_event_aggregation.event_aggregation.each_with_object(INITIAL_STATE.dup) do |event, agg|
          res = aggregate(event, agg)

          agg[:total_units] = res[:total_units]
          agg[:amount] += res[:amount]
        end

        # TODO: cache result for future usage
        aggregation_result.aggregation = aggregation[:total_units]
        aggregation ? aggregation[:amount] : BigDecimal('0')
      end

      def unit_amount
        total_units = aggregation_result.full_units_number || result.units
        return 0 if total_units.zero?

        result.amount / total_units
      end

      delegate :aggregator, to: :aggregation_result

      def custom_aggregator
        properties['aggregator'] || custom_aggregator_sample
      end

      def aggregation_properties
        (properties['aggregation_properties'] || aggregation_properties_sample).with_indifferent_access
      end

      def aggregation_properties_sample
        [
          { from: 0, to: 10, storage_eu: '0', storage_us: '0', storage_asia: '0', fixed_fee: '0' },
          { from: 10, to: 20, storage_eu: '0.10', storage_us: '0.20', storage_asia: '0.30', fixed_fee: '0' },
          { from: 20, to: nil, storage_eu: '0.20', storage_us: '0.30', storage_asia: '0.40', fixed_fee: '0' },
        ]
      end

      def custom_aggregator_sample
        <<~RUBY
          def aggregate(event, previous_state)
            previous_units = previous_state[:total_units]
            event_units = BigDecimal(event.properties['value'].to_s)
            storage_zone = event.properties['storage_zone']

            total_units = previous_units + event_units

            ranges = aggregation_properties['ranges']

            result_amount = ranges.each_with_object(0) do |range, amount|
              # Range was already reached
              next amount if range[:to] && previous_units > range[:to]

              zone_amount = BigDecimal(range[storage_zone.to_sym] || '0')

              if !range[:to] || total_units <= range[:to]
                # Last matching range is reached
                units_to_use = if previous_units > range[:from]
                  event_units # All new units are in the current range
                else
                  total_units - range[:from] # Takes only the new units in the current range
                end

                break amount += zone_amount * units_to_use
              else
                # Range is not the last one
                units_to_use = if previous_units > range[:from]
                  range[:to] - previous_units # All remaining units in the range
                else
                  range[:to] - range[:from] # All units in the range
                end

                amount += zone_amount * units_to_use
              end

              amount
            end

            { total_units: total_units, amount: result_amount }
          end
        RUBY
      end
    end
  end
end
