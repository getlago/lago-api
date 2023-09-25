# frozen_string_literal: true

module Charges
  module ChargeModels
    class ProratedGraduatedService < Charges::ChargeModels::BaseService
      protected

      def ranges
        properties['graduated_ranges']&.map(&:with_indifferent_access)
      end

      def compute_amount
        full_units = per_event_aggregation_result.event_aggregation
        prorated_units = per_event_aggregation_result.event_prorated_aggregation

        index = 0
        full_sum = 0
        overflow = 0
        ranges.reduce(0) do |result_amount, range|
          prorated_sum = 0
          flat_amount = BigDecimal(range[:flat_amount])
          per_unit_amount = BigDecimal(range[:per_unit_amount])

          # NOTE: Add flat amount to the total
          result_amount += flat_amount unless units.zero?

          # Calculate prorated value inside the range. Which events are taken into account
          # for certain range depends on comparing full number of units and range boundaries
          loop do
            # Overflow can happen in scenarios where event covers part of lower range and part of higher range.
            # Here is applied overflow from previous range
            unless overflow.zero?
              prorated_coefficient = prorated_units[index - 1].fdiv(full_units[index - 1])
              prorated_sum += overflow * prorated_coefficient
              full_sum += overflow
              overflow = 0
            end

            # If we are into highest range, the exit condition should happen only if iteration has been performed over
            # all events in this range
            if prorated_units[index].nil?
              result_amount += prorated_sum * per_unit_amount

              return result_amount
            end

            full_sum += full_units[index]
            prorated_sum += prorated_units[index]

            index += 1

            next unless range[:to_value] && full_sum >= range[:to_value]

            # Calculating overflow (if any) and aligning current invalid prorated sum with overflow amount
            overflow = full_sum - range[:to_value]
            prorated_coefficient = prorated_units[index - 1].fdiv(full_units[index - 1])
            prorated_sum -= overflow * prorated_coefficient
            full_sum -= overflow

            break
          end

          result_amount += prorated_sum * per_unit_amount

          result_amount
        end
      end

      def per_event_aggregation_result
        @per_event_aggregation_result ||= aggregation_result.aggregator.per_event_aggregation
      end
    end
  end
end
