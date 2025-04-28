# frozen_string_literal: true

module Types
  module ActivityLogs
    class ActivityTypeTypeEnum < Types::BaseEnum
      description "Activity Logs Types type enums"

      class << self
        DELIMITER = "_"

        def basic_types(record_type, except: [])
          %w[created updated deleted].excluding(except).map do |type|
            "#{record_type}#{DELIMITER}#{type}"
          end
        end

        def invoice_types
          %w[drafted failed created paid_credit_added generated payment_status_updated payment_overdue voided payment_failure].map do |type|
            "invoice#{DELIMITER}#{type}"
          end
        end

        def payment_receipts_types
          %w[created generated].map do |type|
            "payment_receipt#{DELIMITER}#{type}"
          end
        end

        def credit_note_types
          %w[created generated refund_failure].map do |type|
            "credit_note#{DELIMITER}#{type}"
          end
        end

        def subscription_types
          %w[started terminated updated].map do |type|
            "subscription#{DELIMITER}#{type}"
          end
        end

        def wallet_transaction_types
          %w[payment_failure].map do |type|
            "wallet_transaction#{DELIMITER}#{type}"
          end + basic_types("wallet_transaction", except: ["deleted"])
        end

        def payment_types
          ["payment#{DELIMITER}recorded"]
        end
      end

      [
        *basic_types("billable_metric"),
        *basic_types("plan"),
        *basic_types("customer"),
        *invoice_types,
        *payment_receipts_types,
        *credit_note_types,
        *basic_types("billing_entities"),
        *subscription_types,
        *basic_types("wallet", except: ["deleted"]),
        *wallet_transaction_types,
        *payment_types,
        *basic_types("coupon"),
        *basic_types("applied_coupon", except: ["updated"])
      ].each do |type|
        value type
      end
    end
  end
end
