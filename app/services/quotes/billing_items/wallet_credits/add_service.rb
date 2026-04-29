# frozen_string_literal: true

module Quotes
  module BillingItems
    module WalletCredits
      class AddService < Quotes::BillingItems::BaseMutationService
        ALLOWED_ORDER_TYPES = %w[subscription_creation subscription_amendment].freeze
        RECURRING_RULE_PREFIX = "qtrr"

        def initialize(quote_version:, params:)
          @quote_version = quote_version
          @params = params
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote_version") unless quote_version
          return result.forbidden_failure! unless quote_version.organization.feature_flag_enabled?(:order_forms)
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote_version.draft?

          unless ALLOWED_ORDER_TYPES.include?(quote_version.quote.order_type)
            return result.validation_failure!(
              errors: {billing_item: ["wallet_credits not allowed for one_off order type"]}
            )
          end

          item = params.transform_keys(&:to_s)
          item["id"] ||= "qtw_#{SecureRandom.uuid}"
          item["recurring_transaction_rules"] = normalize_recurring_rules(
            item.fetch("recurring_transaction_rules", [])
          )

          persist_items("wallet_credits", current_items("wallet_credits") + [item])
        end

        private

        attr_reader :params

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
