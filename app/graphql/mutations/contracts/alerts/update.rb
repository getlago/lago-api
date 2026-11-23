# frozen_string_literal: true

module Mutations
  module Contracts
    module Alerts
      class Update < BaseMutation
        include RequiresProductCatalog
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "contracts:update"

        graphql_name "UpdateContractAlert"
        description "Updates the name and the thresholds of a contract alert"

        input_object_class Types::UsageMonitoring::ContractAlerts::UpdateInput
        type Types::UsageMonitoring::ContractAlerts::Object

        def resolve(id:, **args)
          args[:thresholds] = args[:thresholds]&.map(&:to_h) if args.key?(:thresholds)

          result = ::UsageMonitoring::ContractAlerts::UpdateService.call(
            alert: current_organization.contract_alerts.find_by(id:),
            params: args
          )

          result.success? ? result.alert : result_error(result)
        end
      end
    end
  end
end
