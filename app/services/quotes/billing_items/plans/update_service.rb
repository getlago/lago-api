# frozen_string_literal: true

module Quotes
  module BillingItems
    module Plans
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

          items = current_items("plans")
          item_index = items.index { |item| item["id"] == id }
          return result.not_found_failure!(resource: "billing_item") if item_index.nil?

          updated_item = items[item_index].merge(params.transform_keys(&:to_s))

          plan_id = updated_item["plan_id"]

          if plan_id.blank?
            return result.validation_failure!(
              errors: {billing_item: ["plan_id is required"]}
            )
          end

          unless quote.organization.plans.exists?(id: plan_id)
            return result.validation_failure!(
              errors: {billing_item: ["plan not found in organization"]}
            )
          end

          items[item_index] = updated_item
          persist_items("plans", items)
        end

        private

        attr_reader :id, :params
      end
    end
  end
end
