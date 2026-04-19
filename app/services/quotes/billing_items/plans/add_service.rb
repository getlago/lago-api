# frozen_string_literal: true

module Quotes
  module BillingItems
    module Plans
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
              errors: {billing_item: ["plans not allowed for one_off order type"]}
            )
          end

          plan_id = params[:plan_id] || params["plan_id"]

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

          item = params.transform_keys(&:to_s)
          item["id"] ||= "qtp_#{SecureRandom.uuid}"

          persist_items("plans", current_items("plans") + [item])
        end

        private

        attr_reader :params
      end
    end
  end
end
