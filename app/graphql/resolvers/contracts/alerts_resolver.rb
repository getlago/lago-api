# frozen_string_literal: true

module Resolvers
  module Contracts
    class AlertsResolver < Resolvers::BaseResolver
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:view"

      description "Query the alerts of a contract, which follow its external id"

      argument :contract_id, ID, required: true, description: "Unique ID of the contract, in any status"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::UsageMonitoring::ContractAlerts::Object.collection_type, null: false

      def resolve(contract_id:, page: nil, limit: nil)
        contract = current_organization.contracts.find_by(id: contract_id)

        if contract
          ::UsageMonitoring::ContractAlertsQuery.call(
            organization: current_organization,
            filters: {contract_external_id: contract.external_id},
            pagination: {page:, limit:}
          ).contract_alerts
        else
          not_found_error(resource: "contract")
        end
      end
    end
  end
end
