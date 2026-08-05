# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      class StructuralValidator < ::BaseValidator
        def initialize(result, billing_items:, scope:)
          @billing_items = billing_items || {}
          @scope = scope

          super
        end

        def valid?
          Schema.schemer(scope).validate(billing_items).each do |schema_error|
            add_schema_error(schema_error)
          end

          if errors?
            result.validation_failure!(errors:)
            return false
          end

          true
        end

        private

        attr_reader :billing_items, :scope

        def add_schema_error(schema_error)
          if schema_error["type"] == "required"
            schema_error.dig("details", "missing_keys").each do |missing_key|
              field = field_for("#{schema_error["data_pointer"]}/#{missing_key}")
              add_error(field:, error_code: code_for(schema_error))
            end
          else
            add_error(field: field_for(schema_error["data_pointer"]), error_code: code_for(schema_error))
          end
        end

        def field_for(pointer)
          ["billing_items", *pointer.split("/").reject(&:empty?)].join(".").to_sym
        end

        def code_for(schema_error)
          if schema_error["x-error"]
            schema_error["error"]
          else
            "is_invalid"
          end
        end
      end
    end
  end
end
