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
        units_count = prorated_units.count
        index = 0
        full_sum = 0
        overflow = 0

        # From each tier correct amounts need to be fetched
        ranges.reduce(0) do |result_amount, range|
          prorated_sum = 0
          flat_amount = BigDecimal(range[:flat_amount])
          per_unit_amount = BigDecimal(range[:per_unit_amount])

          # NOTE: Add flat amount to the total
          result_amount += flat_amount if !units.zero? && (!overflow.zero? || prorated_units[index])

          # Calculate total prorated value inside the tier. The goal is to iterate over both arrays (prorated and full)
          # and determine which prorated events goes into certain tier. Full units sum determines tier while
          # prorated units sum determines amount that is going to be used for price calculation inside the tier.
          # Overflow can happen if event value covers partially both lower and higher tier
          while (index < units_count) || !overflow.zero?
            # Here is applied overflow from previous iteration (if any)
            unless overflow.zero?
              prorated_sum += overflow * prorated_coefficient(prorated_units[index - 1], full_units[index - 1])

              # This condition handles multiple overflows. E.g. We have two tiers: 0 - 5, 6 - inf.
              # There is only one event whose value is 75. There will be overflow for each tier and we need to
              # calculate it for each tier
              if range[:to_value] && full_sum >= range[:to_value]
                overflow = full_sum - range[:to_value]
                prorated_sum -= overflow * prorated_coefficient(prorated_units[index - 1], full_units[index - 1])

                break
              end

              overflow = 0
            end

            # If we are into highest range and overflow is handled we should exit the loop if there is no more events
            break if prorated_units[index].nil?

            full_sum += full_units[index]
            prorated_sum += prorated_units[index]

            index += 1

            next unless range[:to_value] && full_sum >= range[:to_value]

            # Calculating overflow (if any) and aligning current invalid prorated sum with prorated overflow amount
            overflow = full_sum - range[:to_value]
            prorated_sum -= overflow * prorated_coefficient(prorated_units[index - 1], full_units[index - 1])

            break
          end

          result_amount += prorated_sum * per_unit_amount

          result_amount
        end
      end

      private

      def per_event_aggregation_result
        @per_event_aggregation_result ||= aggregation_result.aggregator.per_event_aggregation
      end

      def prorated_coefficient(prorated_value, full_value)
        prorated_value.fdiv(full_value)
      end
    end
  end
end
