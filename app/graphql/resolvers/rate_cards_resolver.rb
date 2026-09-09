# frozen_string_literal: true

module Resolvers
  class RateCardsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "rate_cards:view"

    description "Query rate cards of an organization"

    argument :code, String, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_code, String, required: false
    argument :product_filter_code, String, required: false
    argument :product_filter_id, ID, required: false
    argument :product_id, ID, required: false
    argument :search_term, String, required: false

    type Types::RateCards::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_id: nil, product_filter_id: nil, code: nil, product_code: nil, product_filter_code: nil)
      result = ::RateCardsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_id:, product_filter_id:, code:, product_code:, product_filter_code:}
      )

      result.rate_cards
    end
  end
end
