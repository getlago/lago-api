# frozen_string_literal: true

module Resolvers
  class RateCardsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "rate_cards:view"

    description "Query rate cards of an organization"

    argument :code, String, required: false
    argument :currency, Types::CurrencyEnum, required: false
    argument :exclude_priced_on_contract_id, ID, required: false
    argument :exclude_priced_on_plan_id, ID, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_category_ids, [ID], required: false
    argument :product_code, String, required: false
    argument :product_filter_code, String, required: false
    argument :product_filter_ids, [ID], required: false
    argument :product_ids, [ID], required: false
    argument :search_term, String, required: false
    argument :without_product_category, Boolean, required: false

    type Types::RateCards::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_ids: nil, product_filter_ids: nil, product_category_ids: nil, without_product_category: nil, code: nil, currency: nil, product_code: nil, product_filter_code: nil, exclude_priced_on_plan_id: nil, exclude_priced_on_contract_id: nil)
      # Excluding the priced cards tells how the plan or contract is priced.
      raise not_enough_permissions_error("plans:view") if exclude_priced_on_plan_id && !context.dig(:permissions, "plans:view")
      raise not_enough_permissions_error("contracts:view") if exclude_priced_on_contract_id && !context.dig(:permissions, "contracts:view")

      result = ::RateCardsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_ids:, product_filter_ids:, product_category_ids:, without_product_category:, code:, currency:, product_code:, product_filter_code:, exclude_priced_on_plan_id:, exclude_priced_on_contract_id:}
      )

      result.success? ? result.rate_cards : result_error(result)
    end
  end
end
