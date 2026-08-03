# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      module Schema
        UPDATE_DEFINITION = {
          "type" => "object",
          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
          "properties" => {
            "plans" => {
              "type" => "array",
              "x-error" => {"type" => "invalid_type", "minItems" => "invalid_count"},
              "items" => {
                "type" => "object",
                "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                "required" => %w[id localId type payload],
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
                  "type" => {
                    "type" => "string",
                    "const" => "plan",
                    "x-error" => {"type" => "invalid_type", "const" => "invalid_value"}
                  },
                  "payload" => {
                    "type" => "object",
                    "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                    "properties" => {
                      "code" => {
                        "type" => "string",
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      }
                    }
                  },
                  "overrides" => {
                    "type" => "object",
                    "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                    "x-error" => {"type" => "invalid_type"},
                    "properties" => {
                      "amountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "charges" => {
                        "type" => "array",
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "required" => ["id"],
                          "properties" => {
                            "id" => {
                              "type" => "string",
                              "format" => "uuid",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "properties" => {
                              "type" => "object",
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "minAmountCents" => {
                              "type" => "integer",
                              "minimum" => 0,
                              "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                            },
                            "invoiceDisplayName" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            }
                          }
                        }
                      },
                      "fixedCharges" => {
                        "type" => "array",
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "required" => ["id"],
                          "properties" => {
                            "id" => {
                              "type" => "string",
                              "format" => "uuid",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "units" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            },
                            "properties" => {
                              "type" => "object",
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "invoiceDisplayName" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            },
            "coupons" => {
              "type" => "array",
              "x-error" => {"type" => "invalid_type"},
              "items" => {
                "type" => "object",
                "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                "required" => %w[id localId type payload],
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
                  "type" => {
                    "type" => "string",
                    "const" => "coupon",
                    "x-error" => {"type" => "invalid_type", "const" => "invalid_value"}
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
                      "couponType" => {
                        "type" => "string",
                        "enum" => %w[fixed_amount percentage],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "amountCents" => {
                        "type" => "integer",
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "amountCurrency" => {
                        "type" => "string",
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "percentageRate" => {
                        "type" => "number",
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "frequency" => {
                        "type" => "string",
                        "enum" => %w[once recurring forever],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "frequencyDuration" => {
                        "type" => "integer",
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      }
                    }
                  }
                }
              }
            },
            "wallets" => {
              "type" => "array",
              "x-error" => {"type" => "invalid_type"},
              "items" => {
                "type" => "object",
                "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                "required" => %w[localId type payload],
                "properties" => {
                  "localId" => {
                    "type" => "string",
                    "minLength" => 1,
                    "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                  },
                  "type" => {
                    "type" => "string",
                    "const" => "wallet",
                    "x-error" => {"type" => "invalid_type", "const" => "invalid_value"}
                  },
                  "payload" => {
                    "type" => "object",
                    "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                    "properties" => {
                      "paidCredits" => {
                        "type" => "string",
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "grantedCredits" => {
                        "type" => "string",
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "rateAmount" => {
                        "type" => "string",
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "recurringTransactionRules" => {
                        "type" => "array",
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type"},
                          "properties" => {
                            "trigger" => {
                              "type" => "string",
                              "enum" => %w[interval threshold],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "interval" => {
                              "type" => "string",
                              "enum" => %w[weekly monthly quarterly yearly semiannual],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "method" => {
                              "type" => "string",
                              "enum" => %w[fixed target],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "thresholdCredits" => {
                              "type" => "string",
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "targetOngoingBalance" => {
                              "type" => "string",
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "paidCredits" => {
                              "type" => "string",
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "grantedCredits" => {
                              "type" => "string",
                              "x-error" => {"type" => "invalid_type"}
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }.freeze

        APPROVE_DEFINITION = UPDATE_DEFINITION.deep_dup.tap do |schema|
          schema["required"] = ["plans"]

          plans = schema["properties"]["plans"]
          plans["minItems"] = 1
          plans["items"]["properties"]["payload"]["required"] = %w[code]

          schema["properties"]["coupons"]["items"]["properties"]["payload"]["required"] =
            %w[code couponType]
          schema["properties"]["wallets"]["items"]["properties"]["payload"]["required"] =
            %w[paidCredits grantedCredits rateAmount]
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
