# frozen_string_literal: true

module Charges
  module Validators
    class PackageService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_amount unless valid_amount?
        errors << :invalid_free_units unless valid_free_units?
        errors << :invalid_package_size unless valid_package_size?

        return result.fail!(:invalid_properties, errors) if errors.present?

        result
      end

      private

      def amount_cents
        properties['amount_cents']
      end

      def valid_amount?
        amount_cents.present? && amount_cents.is_a?(Integer) && amount_cents >= 0
      end

      def package_size
        properties['package_size']
      end

      def valid_package_size?
        package_size.present? && package_size.is_a?(Integer) && package_size.positive?
      end

      def free_units
        properties['free_units']
      end

      def valid_free_units?
        free_units.present? && free_units.is_a?(Integer) && free_units >= 0
      end
    end
  end
end
