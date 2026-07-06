# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      module Schema
        def self.definition(strict:)
          root = {
            "type" => "object",
            "additionalProperties" => unsupported_key_definition,
            "properties" => {"addons" => addons_definition(strict:)},
            "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"}
          }

          if strict
            root["required"] = ["addons"]
          end

          root
        end

        def self.addons_definition(strict:)
          addons = {
            "type" => "array",
            "items" => addon_definition(strict:),
            "x-error" => {"type" => "invalid_type", "minItems" => "invalid_count"}
          }

          if strict
            addons["minItems"] = 1
          end

          addons
        end

        def self.addon_definition(strict:)
          {
            "type" => "object",
            "additionalProperties" => unsupported_key_definition,
            "required" => strict ? %w[id localId payload] : %w[id localId],
            "properties" => {
              "id" => {
                "type" => "string",
                "format" => "uuid",
                "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
              },
              "localId" => {
                "type" => "string",
                "minLength" => 1,
                "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
              },
              "payload" => payload_definition(strict:),
              "overrides" => overrides_definition
            },
            "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"}
          }
        end

        def self.payload_definition(strict:)
          payload = {
            "type" => "object",
            "additionalProperties" => unsupported_key_definition,
            "properties" => {
              "code" => {
                "type" => "string",
                "minLength" => 1,
                "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
              },
              "units" => {
                "type" => "number",
                "exclusiveMinimum" => 0,
                "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
              },
              "unit_amount_cents" => amount_definition,
              "total_amount_cents" => amount_definition,
              "invoice_display_name" => {
                "type" => %w[string null],
                "x-error" => {"type" => "invalid_type"}
              },
              "from_datetime" => datetime_definition,
              "to_datetime" => datetime_definition
            },
            "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"}
          }

          if strict
            payload["required"] = %w[code units unit_amount_cents total_amount_cents]
          end

          payload
        end

        def self.overrides_definition
          {
            "type" => "object",
            "additionalProperties" => unsupported_key_definition,
            "properties" => {
              "unit_amount_cents" => amount_definition,
              "total_amount_cents" => amount_definition
            },
            "x-error" => {"type" => "invalid_type"}
          }
        end

        def self.unsupported_key_definition
          {"not" => {}, "x-error" => "unsupported_key"}
        end

        def self.amount_definition
          {
            "type" => "integer",
            "minimum" => 0,
            "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
          }
        end

        def self.datetime_definition
          {
            "type" => %w[string null],
            "format" => "date-time",
            "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
          }
        end

        SCHEMERS = {
          update: JSONSchemer.schema(definition(strict: false)),
          approve: JSONSchemer.schema(definition(strict: true))
        }.freeze

        private_class_method :definition, :addons_definition, :addon_definition,
          :payload_definition, :overrides_definition, :unsupported_key_definition,
          :amount_definition, :datetime_definition

        def self.schemer(scope)
          SCHEMERS.fetch(scope)
        end
      end
    end
  end
end
