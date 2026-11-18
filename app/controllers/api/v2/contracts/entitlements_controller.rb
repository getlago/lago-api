# frozen_string_literal: true

module Api
  module V2
    module Contracts
      # The entitlements of a contract: the v1 request body, the v2 contract entitlement shape and the v2 errors.
      class EntitlementsController < Api::V2::BaseController
        include Api::EntitlementsErrors

        serializable_with ::V2::ContractEntitlementSerializer, root: :entitlement, expand_on: []

        # Before the lookup, like the cursor of the paginated lists.
        before_action :reject_pagination!
        before_action :find_contract

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

        # Without a status, the live contract (the pending one first); with one, the latest of that status.
        def find_contract
          status = params[:status]
          contracts = current_organization.contracts
          external_id = params[:external_id]

          if status.blank?
            @contract = contracts.live_by_external_id(external_id)
          elsif Contract::STATUSES.value?(status)
            @contract = contracts.latest_by_external_id(external_id, status:)
          else
            return validation_errors(errors: {status: ["value_is_invalid"]}, meta: {status: {allowed_values: Contract::STATUSES.values}})
          end

          not_found_error(resource: "contract") unless @contract
        end

        def resource_name
          "contract"
        end
      end
    end
  end
end
