# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      module Schema
        def self.definition(strict:)
          root = {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {"addons" => addons_definition(strict:)}
          }
          root["required"] = ["addons"] if strict
          root
        end

        def self.addons_definition(strict:)
          addons = {
            "type" => "array",
            "items" => addon_definition(strict:)
          }
          addons["minItems"] = 1 if strict
          addons
        end

        def self.addon_definition(strict:)
          {
            "type" => "object",
            "additionalProperties" => false,
            "required" => strict ? %w[id localId payload] : %w[id localId],
            "properties" => {
              "id" => {"type" => "string", "format" => "uuid"},
              "localId" => {"type" => "string", "minLength" => 1},
              "payload" => payload_definition(strict:),
              "overrides" => overrides_definition
            }
          }
        end

        def self.payload_definition(strict:)
          payload = {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "code" => {"type" => "string", "minLength" => 1},
              "units" => {"type" => "number", "exclusiveMinimum" => 0},
              "unit_amount_cents" => amount_definition,
              "total_amount_cents" => amount_definition,
              "invoice_display_name" => {"type" => %w[string null]},
              "from_datetime" => datetime_definition,
              "to_datetime" => datetime_definition
            }
          }
          payload["required"] = %w[code units unit_amount_cents total_amount_cents] if strict
          payload
        end

        def self.overrides_definition
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "unit_amount_cents" => amount_definition,
              "total_amount_cents" => amount_definition
            }
          }
        end

        def self.amount_definition
          {"type" => "integer", "minimum" => 0}
        end

        def self.datetime_definition
          {"type" => %w[string null], "format" => "date-time"}
        end

        SCHEMERS = {
          update: JSONSchemer.schema(definition(strict: false)),
          approve: JSONSchemer.schema(definition(strict: true))
        }.freeze

        private_class_method :definition, :addons_definition, :addon_definition,
          :payload_definition, :overrides_definition, :amount_definition, :datetime_definition

        def self.schemer(scope)
          SCHEMERS.fetch(scope)
        end
      end
    end
  end
end
