# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      module Schema
        CURRENCIES = Currencies::ACCEPTED_CURRENCIES.keys.map(&:to_s).freeze

        CHARGE_MODELS = Charge::CHARGE_MODELS.map(&:to_s).freeze
        FIXED_CHARGE_MODELS = FixedCharge::CHARGE_MODELS.keys.map(&:to_s).freeze

        COUPON_TYPES = Coupon::COUPON_TYPES.map(&:to_s).freeze
        COUPON_FREQUENCIES = Coupon::FREQUENCIES.map(&:to_s).freeze

        RULE_TRIGGERS = RecurringTransactionRule::TRIGGERS.map(&:to_s).freeze
        RULE_INTERVALS = RecurringTransactionRule::INTERVALS.map(&:to_s).freeze
        RULE_METHODS = RecurringTransactionRule::METHODS.map(&:to_s).freeze

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
                  # Catalog snapshot: free-form, except the keys the execution flow consumes.
                  # startDate/endDate carry no format on purpose, the business validator applies
                  # the same ISO 8601 check as Subscriptions::ValidateService so an approved quote
                  # is never stricter than the service it feeds.
                  "payload" => {
                    "type" => "object",
                    "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                    "properties" => {
                      "code" => {
                        "type" => "string",
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "subscriptionExternalId" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "subscriptionName" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "billingTime" => {
                        "type" => %w[string null],
                        "enum" => [*Subscription::BILLING_TIME.map(&:to_s), nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "startDate" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "endDate" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "paymentMethodId" => {
                        "type" => %w[string null],
                        "format" => "uuid",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      },
                      # Charge overrides are keyed by billableMetricCode while
                      # Plans::OverrideService keys by charge id, so the id is resolved through
                      # this snapshot: it pins the charge the approver was looking at.
                      "charges" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "x-error" => {"type" => "invalid_type"},
                          "properties" => {
                            "id" => {
                              "type" => "string",
                              "format" => "uuid",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "billableMetric" => {
                              "type" => "object",
                              "x-error" => {"type" => "invalid_type"},
                              "properties" => {
                                "code" => {
                                  "type" => "string",
                                  "minLength" => 1,
                                  "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                                }
                              }
                            },
                            "chargeModel" => {
                              "type" => %w[string null],
                              "enum" => [*CHARGE_MODELS, nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            }
                          }
                        }
                      },
                      "fixedCharges" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        "items" => {
                          "type" => "object",
                          "x-error" => {"type" => "invalid_type"},
                          "properties" => {
                            "id" => {
                              "type" => "string",
                              "format" => "uuid",
                              "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                            },
                            "addOn" => {
                              "type" => "object",
                              "x-error" => {"type" => "invalid_type"},
                              "properties" => {
                                "code" => {
                                  "type" => "string",
                                  "minLength" => 1,
                                  "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                                }
                              }
                            },
                            "chargeModel" => {
                              "type" => %w[string null],
                              "enum" => [*FIXED_CHARGE_MODELS, nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            }
                          }
                        }
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
                      # Plans::OverrideService reprices the duplicated plan in this currency, which is
                      # how a plan from the catalog is quoted in the currency of the deal.
                      "amountCurrency" => {
                        "type" => %w[string null],
                        "enum" => CURRENCIES + [nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_currency"}
                      },
                      "invoiceDisplayName" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "name" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "description" => {
                        "type" => %w[string null],
                        "minLength" => 1,
                        "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                      },
                      "trialPeriod" => {
                        "type" => %w[number null],
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "minimumCommitment" => {
                        "type" => %w[object null],
                        "additionalProperties" => {"not" => {}, "x-error" => "unsupported_key"},
                        "x-error" => {"type" => "invalid_type"},
                        "properties" => {
                          "amountCents" => {
                            "type" => %w[integer null],
                            "exclusiveMinimum" => 0,
                            "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
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
                              "exclusiveMinimum" => 0,
                              "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
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
                            # NOTE: chargeModel is stored for the execution flow to consume,
                            # Charges::OverrideService cannot switch models yet. properties is
                            # deliberately only type-checked: its shape per charge model is
                            # validated where the override is applied, not here.
                            "chargeModel" => {
                              "type" => %w[string null],
                              "enum" => [*CHARGE_MODELS, nil],
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
                        "enum" => COUPON_TYPES,
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                      },
                      "amountCents" => {
                        "type" => %w[integer null],
                        "minimum" => 0,
                        "x-error" => {"type" => "invalid_type", "minimum" => "invalid_value"}
                      },
                      "currency" => {
                        "type" => %w[string null],
                        "enum" => CURRENCIES + [nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_currency"}
                      },
                      "percentageRate" => {
                        "type" => %w[number null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "frequency" => {
                        "type" => %w[string null],
                        "enum" => [*COUPON_FREQUENCIES, nil],
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
                      # AppliedCoupons::CreateService applies the coupon in this currency, which is
                      # how a catalog coupon is quoted in the currency of the deal.
                      "amountCurrency" => {
                        "type" => %w[string null],
                        "enum" => CURRENCIES + [nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_currency"}
                      },
                      "percentageRate" => {
                        "type" => %w[number null],
                        "exclusiveMinimum" => 0,
                        "x-error" => {"type" => "invalid_type", "exclusiveMinimum" => "invalid_value"}
                      },
                      "frequency" => {
                        "type" => %w[string null],
                        "enum" => [*COUPON_FREQUENCIES, nil],
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
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "grantedCredits" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "rateAmount" => {
                        "type" => %w[string null],
                        "x-error" => {"type" => "invalid_type"}
                      },
                      "currency" => {
                        "type" => %w[string null],
                        "enum" => CURRENCIES + [nil],
                        "x-error" => {"type" => "invalid_type", "enum" => "invalid_currency"}
                      },
                      "expirationAt" => {
                        "type" => %w[string null],
                        "format" => "date-time",
                        "x-error" => {"type" => "invalid_type", "format" => "invalid_format"}
                      },
                      "appliesTo" => {
                        "type" => %w[object null],
                        "x-error" => {"type" => "invalid_type"},
                        "properties" => {
                          "feeTypes" => {
                            "type" => %w[array null],
                            "x-error" => {"type" => "invalid_type"},
                            "items" => {
                              "type" => "string",
                              "enum" => Fee::FEE_TYPES.map(&:to_s),
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            }
                          },
                          "billableMetricCodes" => {
                            "type" => %w[array null],
                            "x-error" => {"type" => "invalid_type"},
                            "items" => {
                              "type" => "string",
                              "minLength" => 1,
                              "x-error" => {"type" => "invalid_type", "minLength" => "invalid_value"}
                            }
                          }
                        }
                      },
                      "recurringTransactionRules" => {
                        "type" => %w[array null],
                        "x-error" => {"type" => "invalid_type"},
                        # NOTE: rules live inside the free-form payload, so unknown keys are
                        # accepted here too. Only the keys the validators act on are typed.
                        "items" => {
                          "type" => "object",
                          "x-error" => {"type" => "invalid_type", "required" => "value_is_mandatory"},
                          "properties" => {
                            "trigger" => {
                              "type" => %w[string null],
                              "enum" => [*RULE_TRIGGERS, nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "interval" => {
                              "type" => %w[string null],
                              "enum" => [*RULE_INTERVALS, nil],
                              "x-error" => {"type" => "invalid_type", "enum" => "invalid_value"}
                            },
                            "method" => {
                              "type" => %w[string null],
                              "enum" => [*RULE_METHODS, nil],
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
                            "grantsTargetTopUp" => {
                              "type" => %w[boolean null],
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

          # An override is resolved through its snapshot entry, by code then by id, so an approved
          # entry must carry both. Without the id the business validator can only report
          # charge_not_found against the override, pointing the approver at the wrong key.
          charge_snapshot = plans["items"]["properties"]["payload"]["properties"]["charges"]["items"]
          charge_snapshot["required"] = ["id"]
          charge_snapshot["x-error"]["required"] = "value_is_mandatory"
          charge_snapshot["properties"]["billableMetric"]["required"] = ["code"]
          charge_snapshot["properties"]["billableMetric"]["x-error"]["required"] = "value_is_mandatory"

          fixed_charge_snapshot = plans["items"]["properties"]["payload"]["properties"]["fixedCharges"]["items"]
          fixed_charge_snapshot["required"] = ["id"]
          fixed_charge_snapshot["x-error"]["required"] = "value_is_mandatory"
          fixed_charge_snapshot["properties"]["addOn"]["required"] = ["code"]
          fixed_charge_snapshot["properties"]["addOn"]["x-error"]["required"] = "value_is_mandatory"

          schema["properties"]["coupons"]["items"]["properties"]["payload"]["required"] =
            %w[code type]

          wallet_credit_payload = schema["properties"]["walletCredits"]["items"]["properties"]["payload"]
          wallet_credit_payload["required"] = %w[paidCredits grantedCredits rateAmount]
          wallet_credit_payload["required"].each do |key|
            wallet_credit_payload["properties"][key]["type"] = "string"
          end

          # Wallets::ValidateService rejects more than one rule per wallet, so approving two is
          # approving something that cannot be created.
          recurring_rules = wallet_credit_payload["properties"]["recurringTransactionRules"]
          recurring_rules["maxItems"] = 1
          recurring_rules["x-error"]["maxItems"] = "invalid_count"

          rules = recurring_rules["items"]
          rules["required"] = ["trigger"]
          rules["properties"]["trigger"]["type"] = "string"
          rules["properties"]["trigger"]["enum"] = RULE_TRIGGERS
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
