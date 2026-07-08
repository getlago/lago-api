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
            "addOns" => {
              "type" => "array",
              "x-error" => {"type" => "invalid_type", "minItems" => "invalid_count"},
              "items" => {
                "type" => "object",
                "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                "required" => %w[id localId payload],
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
                  "payload" => {
                    "type" => "object",
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
                      "unitAmountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "totalAmountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "fromDatetime" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      },
                      "toDatetime" => {
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
                      "description" => {
                        "type" => "string",
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "units" => {
                        "type" => "number",
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "unitAmountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "totalAmountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "invoiceDisplayName" => {
                        "type" => "string",
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "fromDatetime" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      },
                      "toDatetime" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      }
                    }
                  }
                }
              }
            }
          }
        }.freeze

        APPROVE_DEFINITION = UPDATE_DEFINITION.deep_dup.tap do |schema|
          schema["required"] = ["addOns"]

          add_ons = schema["properties"]["addOns"]
          add_ons["minItems"] = 1
          add_ons["items"]["properties"]["payload"]["required"] =
            %w[code units unitAmountCents totalAmountCents]
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
