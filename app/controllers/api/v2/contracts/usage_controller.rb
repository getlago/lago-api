# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class UsageController < Api::V2::BaseController
        def current
          contract = active_or_pending_contract
          return not_found_error(resource: "contract") unless contract

          # The column is a PG enum, as on the products index: an unknown type is rejected
          # rather than read as a filter that matches nothing.
          if params[:product_type].present? && !Product::PRODUCT_TYPES.value?(params[:product_type])
            return validation_errors(errors: {product_type: ["value_is_invalid"]})
          end

          result = ::Contracts::CurrentUsageService.call(
            contract:,
            apply_taxes: ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true)),
            filters: ::Contracts::CurrentUsageService::Filters.new(**filter_params)
          )

          if result.success?
            render(json: ::V2::ContractUsageSerializer.new(result, root_name: "current_usage", contract:))
          else
            render_error_response(result)
          end
        end

        private

        # A pending replacement does not hide the active contract: usage accrues on the active one.
        def active_or_pending_contract
          contracts = current_organization.contracts.where(external_id: params[:external_id])

          contracts.active.first || contracts.pending.first
        end

        def filter_params
          params.permit(:rate_card_code, :product_code, :product_filter_code, :product_type).to_h.symbolize_keys
        end

        def resource_name
          "customer_usage"
        end
      end
    end
  end
end
