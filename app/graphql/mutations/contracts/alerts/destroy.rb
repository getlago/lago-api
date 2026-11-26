# frozen_string_literal: true

module Mutations
  module Contracts
    module Alerts
      class Destroy < BaseMutation
        include RequiresProductCatalog
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "contracts:update"

        graphql_name "DestroyContractAlert"
        description "Deletes a contract alert"

        argument :id, ID, required: true

        type Types::UsageMonitoring::ContractAlerts::Object

        def resolve(id:)
          result = ::UsageMonitoring::ContractAlerts::DestroyService.call(
            alert: current_organization.contract_alerts.find_by(id:)
          )

          result.success? ? result.alert : result_error(result)
        end
      end
    end
  end
end
