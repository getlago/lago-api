# frozen_string_literal: true

module Charges
  module ChargeModels
    class PackageService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        return 0 if paid_units.negative?

        # NOTE: Check how many packages (groups of units) are consumed
        #       It's rounded up, because a group counts from its first unit
        package_count = paid_units.fdiv(per_package_size).ceil
        package_count * per_package_unit_amount
      end

      def unit_amount
        return 0 if paid_units <= 0

        compute_amount / paid_units
      end

      def amount_details
        return { free_units: 0, paid_units: 0, per_package_size: 0, per_package_unit_amount: 0 } if units.zero?
        return { free_units:, paid_units: 0, per_package_size:, per_package_unit_amount: } if paid_units.negative?

        {
          free_units:,
          paid_units:,
          per_package_size:,
          per_package_unit_amount:,
        }
      end

      def paid_units
        @paid_units ||= units - free_units
      end

      def free_units
        @free_units ||= properties['free_units'] || 0
      end

      def per_package_size
        @per_package_size ||= properties['package_size']
      end

      def per_package_unit_amount
        @per_package_unit_amount ||= BigDecimal(properties['amount'])
      end
    end
  end
end
