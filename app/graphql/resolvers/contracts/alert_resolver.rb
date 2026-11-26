# frozen_string_literal: true

module Resolvers
  module Contracts
    class AlertResolver < Resolvers::BaseResolver
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:view"

      description "Query a single contract alert"

      argument :id, ID, required: true, description: "Unique ID of the alert"

      type Types::UsageMonitoring::ContractAlerts::Object, null: true

      def resolve(id:)
        current_organization.contract_alerts.find(id)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "alert")
      end
    end
  end
end
