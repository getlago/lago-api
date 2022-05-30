# frozen_string_literal: true

module Charges
  module ChargeModels
    class PackageService < Charges::ChargeModels::BaseService

      protected

      def compute_amount(value)
        # NOTE: exclude free units from the count
        billed_units = value - free_units
        return 0 if billed_units.negative?

        # NOTE: Check how many packages (groups of units) are consumed
        #       It's rounded up, because a group counts from its first unit
        package_count = billed_units.fdiv(package_size).ceil

        package_count * charge.properties['amount_cents']
      end

      def free_units
        charge.properties['free_units'] || 0
      end

      def package_size
        charge.properties['package_size']
      end
    end
  end
end
