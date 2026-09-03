# frozen_string_literal: true

module Resolvers
  class ContractsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query contracts of an organization"

    argument :external_customer_id, String, required: false
    argument :external_id, String, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_code, String, required: false
    argument :status, [Types::Contracts::StatusEnum], required: false

    type Types::Contracts::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, external_customer_id: nil, external_id: nil, plan_code: nil, status: nil)
      result = ::ContractsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {external_customer_id:, external_id:, plan_code:, status:}
      )

      result.contracts
    end
  end
end
