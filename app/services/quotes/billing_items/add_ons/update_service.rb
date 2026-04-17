# frozen_string_literal: true

module Quotes
  module BillingItems
    module AddOns
      class UpdateService < Quotes::BillingItems::BaseMutationService
        def initialize(quote:, id:, params:)
          @quote = quote
          @id = id
          @params = params
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote") unless quote
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote.draft?

          items = current_items("add_ons")
          item_index = items.index { |item| item["id"] == id }
          return result.not_found_failure!(resource: "billing_item") if item_index.nil?

          updated_item = items[item_index].merge(params.transform_keys(&:to_s))

          name = updated_item["name"]
          add_on_id = updated_item["add_on_id"]
          amount_cents = updated_item["amount_cents"]

          if name.blank?
            return result.validation_failure!(
              errors: {billing_item: ["name is required"]}
            )
          end

          if add_on_id.present?
            unless quote.organization.add_ons.exists?(id: add_on_id)
              return result.validation_failure!(
                errors: {billing_item: ["add_on not found in organization"]}
              )
            end
          elsif amount_cents.blank?
            return result.validation_failure!(
              errors: {billing_item: ["amount_cents is required when add_on_id is not provided"]}
            )
          end

          items[item_index] = updated_item
          persist_items("add_ons", items)
        end

        private

        attr_reader :id, :params
      end
    end
  end
end
