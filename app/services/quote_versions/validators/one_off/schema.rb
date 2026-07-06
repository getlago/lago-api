# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      module Schema
        UPDATE_DEFINITION = {
          "type" => "object",
          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
          "properties" => {
            "add_ons" => {
              "type" => "array",
              "x-error" => {"type" => "invalid_type", "minItems" => "invalid_count"},
              "items" => {
                "type" => "object",
                "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                "required" => %w[id local_id],
                "properties" => {
                  "id" => {
                    "type" => "string",
                    "format" => "uuid",
                    "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                  },
                  "local_id" => {
                    "type" => "string",
                    "minLength" => 1,
                    "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                  },
                  "payload" => {
                    "type" => "object",
                    "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                    "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
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
                      "unit_amount_cents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "total_amount_cents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "invoice_display_name" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "from_datetime" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      },
                      "to_datetime" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      }
                    }
                  },
                  "overrides" => {
                    "type" => "object",
                    "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                    "x-error" => {"type" => "invalid_type"},
                    "properties" => {
                      "unit_amount_cents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "total_amount_cents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      }
                    }
                  }
                }
              }
            }
          }
        }.freeze

        APPROVE_DEFINITION = UPDATE_DEFINITION.deep_dup.tap do |schema|
          schema["required"] = ["add_ons"]

          add_ons = schema["properties"]["add_ons"]
          add_ons["minItems"] = 1
          add_ons["items"]["required"] += ["payload"]
          add_ons["items"]["properties"]["payload"]["required"] =
            %w[code units unit_amount_cents total_amount_cents]
        end.freeze

        SCHEMERS = {
          update: JSONSchemer.schema(UPDATE_DEFINITION),
          approve: JSONSchemer.schema(APPROVE_DEFINITION)
        }.freeze

        def self.schemer(scope)
          SCHEMERS.fetch(scope)
        end
      end
    end
  end
end
