# frozen_string_literal: true

module Quotes
  module BillingItems
    module Coupons
      class UpdateService < Quotes::BillingItems::BaseMutationService
        COUPON_TYPES = %w[fixed_amount percentage].freeze

        def initialize(quote:, id:, params:)
          @quote = quote
          @id = id
          @params = params
          super
        end

        def call
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote.draft?

          items = current_items("coupons")
          item_index = items.index { |item| item["id"] == id }
          return result.not_found_failure!(resource: "billing_item") if item_index.nil?

          updated_item = items[item_index].merge(params.transform_keys(&:to_s))

          coupon_id = updated_item["coupon_id"]
          coupon_type = updated_item["coupon_type"]

          if coupon_id.blank?
            return result.validation_failure!(
              errors: {billing_item: ["coupon_id is required"]}
            )
          end

          unless quote.organization.coupons.exists?(id: coupon_id)
            return result.validation_failure!(
              errors: {billing_item: ["coupon not found in organization"]}
            )
          end

          unless COUPON_TYPES.include?(coupon_type.to_s)
            return result.validation_failure!(
              errors: {billing_item: ["coupon_type is invalid"]}
            )
          end

          items[item_index] = updated_item
          persist_items("coupons", items)
        end

        private

        attr_reader :id, :params
      end
    end
  end
end
