# frozen_string_literal: true

module QuoteVersions
  module Validators
    module Schemas
      module OneOff
        CURRENCY_CODES = Currencies::ACCEPTED_CURRENCIES.keys.map(&:to_s).freeze

        # Error codes are declared next to their constraints via "x-error" and
        # surface on the json_schemer error objects; OrderTypeService only
        # anchors them to field keys.
        UPDATE_SCHEMA = {
          "type" => "object",
          "properties" => {
            "currency" => {
              "enum" => CURRENCY_CODES + [nil],
              "x-error" => {"*" => "value_is_invalid"}
            },
            "billing_items" => {
              "type" => "object",
              "additionalProperties" => {"not" => {}, "x-error" => {"*" => "value_is_invalid"}},
              "x-error" => {"*" => "value_is_invalid"},
              "properties" => {
                "add_ons" => {
                  "type" => "array",
                  "x-error" => {"*" => "value_is_invalid"},
                  "items" => {
                    "type" => "object",
                    "x-error" => {"*" => "value_is_invalid"},
                    "properties" => {
                      "payload" => {
                        "type" => "object",
                        "x-error" => {"*" => "value_is_invalid"},
                        "properties" => {
                          "units" => {
                            "type" => ["number", "null"],
                            "exclusiveMinimum" => 0,
                            "x-error" => {"*" => "value_is_invalid"}
                          }
                        }
                      },
                      "overrides" => {
                        "type" => "object",
                        "x-error" => {"*" => "value_is_invalid"}
                      }
                    }
                  }
                }
              }
            }
          }
        }.freeze

        # "not const nil" is the presence check: nil passes the value keywords
        # (they all allow null) and fails only "not", yielding a single
        # value_is_mandatory error instead of a value_is_invalid one.
        APPROVE_SCHEMA = UPDATE_SCHEMA.deep_merge(
          "properties" => {
            "currency" => {
              "not" => {"const" => nil},
              "x-error" => {"not" => "value_is_mandatory"}
            },
            "billing_items" => {
              "required" => ["add_ons"],
              "x-error" => {"required" => "add_ons_required"},
              "properties" => {
                "add_ons" => {
                  "minItems" => 1,
                  "x-error" => {"minItems" => "add_ons_required"},
                  "items" => {
                    "properties" => {
                      "payload" => {
                        "required" => ["units"],
                        "x-error" => {"required" => "value_is_mandatory"},
                        "properties" => {
                          "units" => {
                            "not" => {"const" => nil},
                            "x-error" => {"not" => "value_is_mandatory"}
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        ).freeze

        UPDATE = JSONSchemer.schema(UPDATE_SCHEMA)
        APPROVE = JSONSchemer.schema(APPROVE_SCHEMA)

        def self.for(scope)
          (scope == :approve) ? APPROVE : UPDATE
        end
      end
    end
  end
end
