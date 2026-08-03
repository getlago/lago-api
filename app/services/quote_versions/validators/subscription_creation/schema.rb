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
                "required" => %w[id type payload],
                "properties" => {
                  "id" => {
                    "type" => "string",
                    "format" => "uuid",
                    "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                  },
                  "localId" => {
                    "type" => %w[string null],
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
                    "type" => %w[object null],
                    "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                    "x-error" => {"type" => "invalid_type"},
                    "properties" => {
                      "amountCents" => {
                        "type" => %w[integer null],
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "invoiceDisplayName" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "minimumCommitment" => {
                        "type" => %w[object null],
                        "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                        "x-error" => {"type" => "invalid_type"},
                        "properties" => {
                          "amountCents" => {
                            "type" => %w[integer null],
                            "minimum" => 0,
                            "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                          },
                          "invoiceDisplayName" => {
                            "type" => %w[string null],
                            "minLength" => 1,
                            "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                          }
                        }
                      },
                      "usageThresholds" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "required" => ["amountCents"],
                          "properties" => {
                            "amountCents" => {
                              "type" => "integer",
                              "minimum" => 0,
                              "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                            },
                            "recurring" => {
                              "type" => %w[boolean null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "thresholdDisplayName" => {
                              "type" => %w[string null],
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            }
                          }
                        }
                      },
                      "charges" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "required" => ["billableMetricCode"],
                          "properties" => {
                            "billableMetricCode" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            },
                            "chargeModel" => {
                              "type" => %w[string null],
                              "enum" => [
                                "standard", "graduated", "package", "percentage",
                                "volume", "graduated_percentage", "custom", "dynamic", nil
                              ],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "properties" => {
                              "type" => %w[object null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "minAmountCents" => {
                              "type" => %w[integer null],
                              "minimum" => 0,
                              "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                            },
                            "invoiceDisplayName" => {
                              "type" => %w[string null],
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            }
                          }
                        }
                      },
                      "fixedCharges" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "required" => ["addOnCode"],
                          "properties" => {
                            "addOnCode" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            },
                            "units" => {
                              "type" => %w[string null],
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            },
                            "properties" => {
                              "type" => %w[object null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "invoiceDisplayName" => {
                              "type" => %w[string null],
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
                      "type" => {
                        "type" => "string",
                        "enum" => %w[fixed_amount percentage],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "amountCents" => {
                        "type" => %w[integer null],
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "currency" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "percentageRate" => {
                        "type" => %w[number null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "frequency" => {
                        "type" => %w[string null],
                        "enum" => ["once", "recurring", "forever", nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "frequencyDuration" => {
                        "type" => %w[integer null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      }
                    }
                  },
                  "overrides" => {
                    "type" => %w[object null],
                    "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                    "x-error" => {"type" => "invalid_type"},
                    "properties" => {
                      "amountCents" => {
                        "type" => %w[integer null],
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "percentageRate" => {
                        "type" => %w[number null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "frequency" => {
                        "type" => %w[string null],
                        "enum" => ["once", "recurring", "forever", nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "frequencyDuration" => {
                        "type" => %w[integer null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      }
                    }
                  }
                }
              }
            },
            "walletCredits" => {
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
                    "const" => "wallet_credit",
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
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                          "x-error" => {"type" => "invalid_type"},
                          "properties" => {
                            "trigger" => {
                              "type" => %w[string null],
                              "enum" => ["interval", "threshold", nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "interval" => {
                              "type" => %w[string null],
                              "enum" => ["weekly", "monthly", "quarterly", "yearly", "semiannual", nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "method" => {
                              "type" => %w[string null],
                              "enum" => ["fixed", "target", nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "thresholdCredits" => {
                              "type" => %w[string null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "targetOngoingBalance" => {
                              "type" => %w[string null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "paidCredits" => {
                              "type" => %w[string null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "grantedCredits" => {
                              "type" => %w[string null],
                              "x-error" => {"type" => "invalid_type"}
                            },
                            "startedAt" => {
                              "type" => %w[string null],
                              "format" => "date-time",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "expirationAt" => {
                              "type" => %w[string null],
                              "format" => "date-time",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "transactionName" => {
                              "type" => %w[string null],
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            },
                            "invoiceRequiresSuccessfulPayment" => {
                              "type" => %w[boolean null],
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
            %w[code type]
          schema["properties"]["walletCredits"]["items"]["properties"]["payload"]["required"] =
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
