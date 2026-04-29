# frozen_string_literal: true

module Quotes
  module BillingItems
    module WalletCredits
      class RemoveService < Quotes::BillingItems::BaseMutationService
        def initialize(quote_version:, id:)
          @quote_version = quote_version
          @id = id
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

          items.delete_at(item_index)
          persist_items("wallet_credits", items)
        end

        private

        attr_reader :id
      end
    end
  end
end
