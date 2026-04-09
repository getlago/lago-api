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

        valid_presentation_group_keys = raw_keys.is_a?(Array) && raw_keys.all? do |key|
          next false unless key.is_a?(Hash)

          # NOTE: Support hashes with strings and symbols as keys to avoid issues with different formats
          value_key_present = key.key?("value") || key.key?(:value)
          options_key_valid = !key.key?("options") && !key.key?(:options)

          if key.key?("options") || key.key?(:options)
            options = key["options"] || key[:options]
            options_key_valid = options.is_a?(Hash)
          end

          value_key_present && options_key_valid
        end

        unless valid_presentation_group_keys
          return add_error(
            field: "presentation_group_keys",
            error_code: "presentation_group_keys must be an array of hashes with a 'value' key"
          )
        end

        if raw_keys.size > 2
          add_error(field: "presentation_group_keys", error_code: "presentation_group_keys have a maximum of 2 elements")
        end
      end
    end
  end
end
