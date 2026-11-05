# frozen_string_literal: true

module Resolvers
  class ContractUsagesResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a contract's computed usage for the current billing period, paginated"

    argument :contract_id, ID, required: true
    argument :product_category_ids, [ID], required: false
    argument :without_product_category, Boolean, required: false
    argument :product_ids, [ID], required: false
    argument :product_filter_ids, [ID], required: false
    argument :without_product_filter, Boolean, required: false
    argument :product_type, Types::Products::ProductTypeEnum, required: false
    argument :search_term, String, required: false
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::RateCardUsages::Object.collection_type, null: false

    def resolve(contract_id:, page: 1, limit: 20, search_term: nil, **filters)
      page ||= 1
      limit ||= 20
      return validation_error(messages: {page: ["value_is_out_of_range"]}) unless page.positive?
      return validation_error(messages: {limit: ["value_is_out_of_range"]}) unless limit.positive?

      contract = current_organization.contracts.find_by(id: contract_id)
      return not_found_error(resource: "contract") unless contract

      result = ::Contracts::CurrentUsageService.call(contract:, apply_taxes: false, search_term:, filters:)
      return result_error(result) unless result.success?

      usages = result.rate_card_usages
      offset = (page - 1) * limit
      Kaminari.paginate_array(usages[offset, limit] || [], limit:, offset:, total_count: usages.size)
    end
  end
end
