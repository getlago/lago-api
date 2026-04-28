# frozen_string_literal: true

module Quotes
  module BillingItems
    module WalletCredits
      class UpdateService < Quotes::BillingItems::BaseMutationService
        RECURRING_RULE_PREFIX = "qtrr"

        def initialize(quote_version:, id:, params:)
          @quote_version = quote_version
          @id = id
          @params = params
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote_version") unless quote_version
          return result.forbidden_failure! unless quote_version.organization.feature_flag_enabled?(:order_forms)
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote_version.draft?

          items = current_items("wallet_credits")
          item_index = items.index { |item| item["id"] == id }
          return result.not_found_failure!(resource: "billing_item") if item_index.nil?

          updated_item = items[item_index].merge(params.transform_keys(&:to_s))

          if params.key?(:recurring_transaction_rules) || params.key?("recurring_transaction_rules")
            updated_item["recurring_transaction_rules"] = normalize_recurring_rules(
              updated_item.fetch("recurring_transaction_rules", [])
            )
          end

          items[item_index] = updated_item
          persist_items("wallet_credits", items)
        end

        private

        attr_reader :id, :params

        def normalize_recurring_rules(rules)
          rules.map do |rule|
            rule = rule.transform_keys(&:to_s)
            rule["id"] ||= "#{RECURRING_RULE_PREFIX}_#{SecureRandom.uuid}"
            rule
          end
        end
      end
    end
  end
end
