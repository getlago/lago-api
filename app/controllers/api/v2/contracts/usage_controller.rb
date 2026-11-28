# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class UsageController < Api::V2::BaseController
        include Api::V2::ContractLookup

        serializable_with ::V2::ContractUsageSerializer, root: :current_usage

        def current
          contract = find_contract(params[:external_id])
          return not_found_error(resource: "contract") unless contract

          result = ::Contracts::CurrentUsageService.call(
            contract:,
            apply_taxes: ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true)),
            filters: filter_params,
            use_usage_buckets: true
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
