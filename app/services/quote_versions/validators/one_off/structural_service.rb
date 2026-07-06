# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      class StructuralService
        TYPE_KEYWORDS = %w[type string integer number boolean object array null].freeze

        ERROR_CODES = {
          "format" => "invalid_format",
          "minItems" => "invalid_count",
          "minimum" => "invalid_value",
          "exclusiveMinimum" => "invalid_value",
          "minLength" => "invalid_value"
        }.freeze

        attr_reader :errors

        def initialize(billing_items:, scope:)
          @billing_items = billing_items || {}
          @scope = scope
          @errors = {}
        end

        def valid?
          Schema.schemer(scope).validate(billing_items).each do |schema_error|
            add_schema_error(schema_error)
          end

          errors.empty?
        end

        private

        attr_reader :billing_items, :scope

        def add_schema_error(schema_error)
          if schema_error["type"] == "required"
            schema_error.dig("details", "missing_keys").each do |missing_key|
              add_error(pointer: "#{schema_error["data_pointer"]}/#{missing_key}", code: "value_is_mandatory")
            end
          else
            add_error(pointer: schema_error["data_pointer"], code: error_code(schema_error))
          end
        end

        def add_error(pointer:, code:)
          field = ["billing_items", *pointer.split("/").reject(&:empty?)].join(".").to_sym
          errors[field] ||= []
          errors[field] |= [code]
        end

        def error_code(schema_error)
          type = schema_error["type"]

          if type == "schema" && schema_error["schema_pointer"].end_with?("/additionalProperties")
            "unsupported_key"
          elsif TYPE_KEYWORDS.include?(type)
            "invalid_type"
          else
            ERROR_CODES.fetch(type, "is_invalid")
          end
        end
      end
    end
  end
end
