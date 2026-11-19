# frozen_string_literal: true

module Mutations
  module Contracts
    module Alerts
      class Create < BaseMutation
        include RequiresProductCatalog
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "contracts:update"

        graphql_name "CreateContractAlert"
        description "Creates an alert on a pending or active contract"

        input_object_class Types::UsageMonitoring::ContractAlerts::CreateInput
        type Types::UsageMonitoring::ContractAlerts::Object

        def resolve(contract_id:, **args)
          result = ::UsageMonitoring::ContractAlerts::CreateService.call(
            organization: current_organization,
            contract: current_organization.contracts.find_by(id: contract_id),
            params: args.merge(thresholds: args[:thresholds].map(&:to_h))
          )

          result.success? ? result.alert : result_error(result)
        end
      end
    end
  end
end
