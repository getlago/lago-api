# frozen_string_literal: true

module Quotes
  module BillingItems
    module AddOns
      class AddService < Quotes::BillingItems::BaseMutationService
        ALLOWED_ORDER_TYPES = %w[one_off].freeze

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
              errors: {billing_item: ["add_ons not allowed for subscription order type"]}
            )
          end

          name = params[:name] || params["name"]
          add_on_id = params[:add_on_id] || params["add_on_id"]
          amount_cents = params[:amount_cents] || params["amount_cents"]

          if name.blank?
            return result.validation_failure!(
              errors: {billing_item: ["name is required"]}
            )
          end

          if add_on_id.present?
            unless quote_version.organization.add_ons.exists?(id: add_on_id)
              return result.validation_failure!(
                errors: {billing_item: ["add_on not found in organization"]}
              )
            end
          elsif amount_cents.blank?
            return result.validation_failure!(
              errors: {billing_item: ["amount_cents is required when add_on_id is not provided"]}
            )
          end

          item = params.transform_keys(&:to_s)
          item["id"] ||= "qta_#{SecureRandom.uuid}"

          persist_items("add_ons", current_items("add_ons") + [item])
        end

        private

        attr_reader :params
      end
    end
  end
end
