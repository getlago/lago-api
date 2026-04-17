# frozen_string_literal: true

module Quotes
  module BillingItems
    module Coupons
      class AddService < Quotes::BillingItems::BaseMutationService
        ALLOWED_ORDER_TYPES = %w[subscription_creation subscription_amendment].freeze
        COUPON_TYPES = %w[fixed_amount percentage].freeze

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
              errors: {billing_item: ["coupons not allowed for one_off order type"]}
            )
          end

          coupon_id = params[:coupon_id] || params["coupon_id"]
          coupon_type = params[:coupon_type] || params["coupon_type"]

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

          item = params.transform_keys(&:to_s)
          item["id"] ||= "qtc_#{SecureRandom.uuid}"

          persist_items("coupons", current_items("coupons") + [item])
        end

        private

        attr_reader :params
      end
    end
  end
end
