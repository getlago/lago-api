# frozen_string_literal: true

module Resolvers
  class ContractsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query contracts of an organization"

    argument :billing_entity_ids, [ID], required: false
    argument :external_customer_id, String, required: false
    argument :external_id, String, required: false
    argument :has_rate_overrides, Boolean, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_code, String, required: false
    argument :search_term, String, required: false
    argument :status, [Types::Contracts::StatusEnum], required: false

    type Types::Contracts::Object.collection_type, null: false

    def resolve(
      page: nil,
      limit: nil,
      external_customer_id: nil,
      external_id: nil,
      plan_code: nil,
      status: nil,
      billing_entity_ids: nil,
      has_rate_overrides: nil,
      search_term: nil
    )
      result = ::ContractsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {external_customer_id:, external_id:, plan_code:, status:, billing_entity_ids:, has_rate_overrides:},
        search_term:
      )

      result.contracts
    end
  end
end
