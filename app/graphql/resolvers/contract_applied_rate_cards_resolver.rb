# frozen_string_literal: true

module Resolvers
  class ContractAppliedRateCardsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization
    include RateCardListArguments

    REQUIRED_PERMISSION = "contracts:view"

    description "Query rate cards applied to a contract"

    argument :contract_id, ID, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::ContractAppliedRateCards::Object.collection_type, null: false

    def resolve(contract_id: nil, page: nil, limit: nil, search_term: nil, **filters)
      result = ::ContractRateCardsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: filters.merge(contract_id:),
        search_term:,
        order: :product_category
      )

      result.contract_rate_cards
    end
  end
end
