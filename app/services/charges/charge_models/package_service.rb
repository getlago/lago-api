# frozen_string_literal: true

module Charges
  module ChargeModels
    class PackageService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        # NOTE: exclude free units from the count
        billed_units = units - free_units
        return 0 if billed_units.negative?

        # NOTE: Check how many packages (groups of units) are consumed
        #       It's rounded up, because a group counts from its first unit
        package_count = billed_units.fdiv(package_size).ceil

        package_count * BigDecimal(properties['amount'])
      end

      def free_units
        properties['free_units'] || 0
      end

      def package_size
        properties['package_size']
      end
    end
  end
end
