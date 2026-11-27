# frozen_string_literal: true

module ChargeModels
  module AmountDetails
    class RangeGraduatedPercentageService < ::BaseService
      def initialize(range:, units:)
        super
        @range = range
        @units = units
      end

      def call
        {
          from_value:,
          to_value:,
          flat_unit_amount:,
          rate:,
          units: BigDecimal(units).to_s,
          per_unit_total_amount: per_unit_total_amount.to_s,
          total_with_flat_amount:
        }
      end

      private

      attr_reader :range, :units

      def from_value
        @from_value ||= range[:from_value]
      end

      def to_value
        @to_value ||= range[:to_value]
      end

      def flat_unit_amount
        @flat_unit_amount ||= BigDecimal(range[:flat_amount])
      end

      def rate
        @rate ||= BigDecimal(range[:rate].to_s)
      end

      def per_unit_total_amount
        @per_unit_total_amount ||= units * rate / 100
      end

      def total_with_flat_amount
        @total_with_flat_amount ||= per_unit_total_amount + flat_unit_amount
      end
    end
  end
end
