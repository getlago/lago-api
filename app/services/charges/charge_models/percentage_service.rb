# frozen_string_literal: true

module Charges
  module ChargeModels
    class PercentageService < Charges::ChargeModels::BaseService
      protected

      def compute_amount(value)
        amount = value * BigDecimal(rate)

        return amount if BigDecimal(fixed_amount_value).zero?

        return amount + BigDecimal(fixed_amount_value) if fixed_amount_target == 'all_units'

        amount + (value * BigDecimal(fixed_amount_value))
      end

      # NOTE: FE divides percentage rate with 100 and sends to BE
      def rate
        charge.properties['rate']
      end

      def fixed_amount_value
        charge.properties['fixed_amount_value'] || 0
      end

      def fixed_amount_target
        charge.properties['fixed_amount_target']
      end
    end
  end
end
