# frozen_string_literal: true

module Charges
  module ChargeModels
    class PercentageService < Charges::ChargeModels::BaseService
      protected

      def compute_amount(value)
        compute_percentage_amount(value) + compute_fixed_amount(value)
      end

      def compute_percentage_amount(value)
        value * (rate.fdiv(100))
      end

      def compute_fixed_amount(value)
        return 0 if value.zero?
        return 0 if fixed_amount.nil?

        value * fixed_amount
      end

      # NOTE: FE divides percentage rate with 100 and sends to BE
      def rate
        BigDecimal(charge.properties['rate'])
      end

      def fixed_amount
        @fixed_amount ||= BigDecimal(charge.properties['fixed_amount'] || 0)
      end
    end
  end
end
