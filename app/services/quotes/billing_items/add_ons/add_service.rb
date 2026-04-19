# frozen_string_literal: true

module Quotes
  module BillingItems
    module AddOns
      class AddService < Quotes::BillingItems::BaseMutationService
        def initialize(quote:, params:)
          @quote = quote
          @params = params
          super
        end

        def call
          return result.forbidden_failure! unless License.premium?
          return result.not_found_failure!(resource: "quote") unless quote
          return result.not_allowed_failure!(code: "inappropriate_state") unless quote.draft?

          unless quote.order_type == "one_off"
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
