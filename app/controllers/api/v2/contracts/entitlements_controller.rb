# frozen_string_literal: true

module Api
  module V2
    module Contracts
      # The effective entitlements of a contract, in the v1 subscription body with the v2 errors.
      class EntitlementsController < Api::V2::BaseController
        serializable_with ::V1::Entitlement::ContractEntitlementSerializer, root: :entitlement, expand_on: []

        # The list is returned whole.
        before_action :reject_offset_pagination!

        def index
          status = params[:status]
          return invalid_status_error if status.present? && !Contract::STATUSES.value?(status)

          contract = find_contract(status)
          if contract
            render_entitlements(::Entitlement::SubscriptionEntitlement.for_contract(contract))
          else
            not_found_error(resource: "contract")
          end
        end

        private

        # Without a status, the live contract (the pending one first); with one, the latest of that status.
        def find_contract(status)
          contracts = current_organization.contracts
          external_id = params[:contract_external_id]

          if status.present?
            contracts.latest_by_external_id(external_id, status:)
          else
            contracts.live_by_external_id(external_id)
          end
        end

        def invalid_status_error
          invalid_request_error(
            code: "value_is_invalid",
            error_details: {status: {reason: "value_is_invalid", allowed_values: Contract::STATUSES.values}}
          )
        end

        def resource_name
          "contract"
        end
      end
    end
  end
end
