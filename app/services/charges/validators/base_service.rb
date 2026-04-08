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

        validate_pricing_group_keys
        validate_presentation_group_keys

        if errors?
          result.validation_failure!(errors:)
          return false
        end

        true
      end

      attr_reader :result, :properties

      private

      attr_reader :charge

      def pricing_group_keys
        @pricing_group_keys ||= properties[grouped_key]
      end

      # NOTE: keep accepting grouped_by until the end of the deprecation period
      def grouped_key
        return "pricing_group_keys" unless properties["pricing_group_keys"].nil?

        "grouped_by"
      end

      def validate_pricing_group_keys
        return if pricing_group_keys.nil? || pricing_group_keys.is_a?(Array) && pricing_group_keys.blank?

        if pricing_group_keys.is_a?(Array)
          return if pricing_group_keys.all? { it.is_a?(String) } && pricing_group_keys.all?(&:present?)
        end

        add_error(field: grouped_key, error_code: "invalid_type")
      end

      def validate_presentation_group_keys
        raw_keys = properties["presentation_group_keys"]
        return if raw_keys.blank?

        unless raw_keys.is_a?(Array) && raw_keys.all? { |k| k.is_a?(Hash) && k.key?("value") }
          return add_error(field: "presentation_group_keys", error_code: "presentation_group_keys must be an array of hashes with a 'value' key")
        end

        if raw_keys.size > 2
          add_error(field: "presentation_group_keys", error_code: "presentation_group_keys have a maximum of 2 elements")
        end
      end
    end
  end
end
