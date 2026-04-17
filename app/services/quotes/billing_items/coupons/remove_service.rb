# frozen_string_literal: true

module Quotes
  module BillingItems
    module Coupons
      class RemoveService < Quotes::BillingItems::BaseMutationService
        def initialize(quote:, id:)
          @quote = quote
          @id = id
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote") unless quote
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote.draft?

          items = current_items("coupons")
          item_index = items.index { |item| item["id"] == id }
          return result.not_found_failure!(resource: "billing_item") if item_index.nil?

          items.delete_at(item_index)
          persist_items("coupons", items)
        end

        private

        attr_reader :id
      end
    end
  end
end
