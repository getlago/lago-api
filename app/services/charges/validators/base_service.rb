# frozen_string_literal: true

module Charges
  module Validators
    class BaseService < BaseValidator
      def initialize(charge:, properties: nil)
        @charge = charge
        @properties = properties || charge.properties
        @result = ::BaseService::Result.new

        super(result)
      end

      def valid?
        # NOTE: override and add validation rules

        validate_grouped_by

        if errors?
          result.validation_failure!(errors:)
          return false
        end

        true
      end

      attr_reader :result, :properties

      private

      attr_reader :charge

      def grouped_by
        properties["grouped_by"]
      end

      def validate_grouped_by
        return if grouped_by.nil? || grouped_by.is_a?(Array) && grouped_by.blank?
        return if grouped_by.is_a?(Array) && grouped_by.all? { |f| f.is_a?(String) } && grouped_by.all?(&:present?)

        add_error(field: :grouped_by, error_code: "invalid_type")
      end
    end
  end
end
