# frozen_string_literal: true

module Charges
  module ChargeModels
    class TimebasedService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        per_package_unit_amount
      end

      def unit_amount
        return 0 if paid_units <= 0

        compute_amount / paid_units
      end

      def different_in_minutes
        @different_in_minutes ||= units
      end

      def per_block_time_in_minutes
        @per_block_time_in_minutes ||= properties['block_time_in_minutes']
      end

      def per_package_unit_amount
        @per_package_unit_amount ||= BigDecimal(properties['amount'])
      end

      def paid_units
        @paid_units ||= units
      end
    end
  end
end
