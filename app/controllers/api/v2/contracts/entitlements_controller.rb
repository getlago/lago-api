# frozen_string_literal: true

module Api
  module V2
    module Contracts
      # The entitlements of a contract: the v1 request body, the v2 contract entitlement shape and the v2 errors.
      class EntitlementsController < Api::V2::BaseController
        include Api::EntitlementsErrors
        include Api::V2::ContractLookup

        serializable_with ::V2::ContractEntitlementSerializer, root: :entitlement, expand_on: []

        # Before the lookup, like the cursor of the paginated lists.
        before_action :reject_pagination!
        before_action :load_contract

        def update
          permitted = params.slice(:entitlements).permit(entitlements: {})
          # An empty map is valid: it changes nothing. A missing or non-map value is a 400.
          return missing_parameter_error(ActionController::ParameterMissing.new(:entitlements)) unless permitted.key?(:entitlements)

          result = ::Entitlement::ContractEntitlementUpdateService.call(
            contract:,
            entitlements_params: permitted[:entitlements].to_h
          )

          if result.success?
            render_entitlements(result.entitlements)
          else
            render_entitlements_error(result)
          end
        end

        private

        attr_reader :contract

        def load_contract
          @contract = find_contract(params[:external_id])
          not_found_error(resource: "contract") unless @contract
        end

        def resource_name
          "contract"
        end
      end
    end
  end
end
