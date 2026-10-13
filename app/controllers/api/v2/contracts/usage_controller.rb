# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class UsageController < Api::V2::BaseController
        def current
          contract = active_or_pending_contract
          return not_found_error(resource: "contract") unless contract

          result = ::Contracts::CurrentUsageService.call(
            contract:,
            apply_taxes: ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true)),
            filters: filter_params
          )

          if result.success?
            render(json: ::V2::ContractUsageSerializer.new(result, root_name: "current_usage", contract:))
          else
            render_error_response(result)
          end
        end

        private

        # A pending contract has no usage yet, so it answers an empty list.
        def active_or_pending_contract
          contracts = current_organization.contracts.where(external_id: params[:external_id])

          contracts.active.first || contracts.pending.first
        end

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
