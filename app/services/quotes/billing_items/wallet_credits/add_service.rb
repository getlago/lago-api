# frozen_string_literal: true

module Quotes
  module BillingItems
    module WalletCredits
      class AddService < Quotes::BillingItems::BaseMutationService
        ALLOWED_ORDER_TYPES = %w[subscription_creation subscription_amendment].freeze

        def initialize(quote:, params:)
          @quote = quote
          @params = params
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote") unless quote
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote.draft?

          unless ALLOWED_ORDER_TYPES.include?(quote.order_type)
            return result.validation_failure!(
              errors: {billing_item: ["wallet_credits not allowed for one_off order type"]}
            )
          end

          item = params.transform_keys(&:to_s)
          item["id"] ||= "qtw_#{SecureRandom.uuid}"
          item["recurring_transaction_rules"] = normalize_recurring_rules(item.fetch("recurring_transaction_rules", []))

          persist_items("wallet_credits", current_items("wallet_credits") + [item])
        end

        private

        attr_reader :params

        def normalize_recurring_rules(rules)
          rules.map do |rule|
            rule = rule.transform_keys(&:to_s)
            rule["id"] ||= "qtrr_#{SecureRandom.uuid}"
            rule
          end
        end
      end
    end
  end
end
