# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class UsageController < Api::V2::BaseController
        serializable_with ::V2::ContractUsageSerializer, root: :current_usage

        def current
          # The active contract first; a pending one has no usage yet, so it answers an empty list.
          contract = current_organization.contracts.terminatable_by_external_id(params[:external_id])
          return not_found_error(resource: "contract") unless contract

          result = ::Contracts::CurrentUsageService.call(
            contract:,
            apply_taxes: ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true)),
            filters: filter_params
          )

          if result.success?
            render_current_usage(result)
          else
            render_error_response(result)
          end
        end

        private

        def filter_params
          params.permit(:rate_card_code, :product_code, :product_filter_code, :product_type)
        end

        def resource_name
          "customer_usage"
        end
      end
    end
  end
end
