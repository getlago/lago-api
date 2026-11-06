# frozen_string_literal: true

module Resolvers
  class ContractUsagesResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "contracts:view"

    description "Query a contract's computed usage for the current billing period, paginated"

    argument :contract_id, ID, required: true
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_category_ids, [ID], required: false
    argument :product_filter_ids, [ID], required: false
    argument :product_ids, [ID], required: false
    argument :product_type, Types::Products::ProductTypeEnum, required: false
    argument :search_term, String, required: false
    argument :without_product_category, Boolean, required: false
    argument :without_product_filter, Boolean, required: false

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

      usages = group_by_product(result.rate_card_usages)
      offset = (page - 1) * limit
      Kaminari.paginate_array(usages[offset, limit] || [], limit:, offset:, total_count: usages.size)
    end

    private

    # The service orders usages chronologically - a contract it shares with the public REST API,
    # so that order stays untouched there. Re-grouped here, after it, so a product's rate cards
    # (and its filter variants) land contiguous before the page slice: a page boundary splitting
    # them would otherwise repeat the product's name on more than one page. Stable (keyed with the
    # original index) so ties keep the service's chronological order.
    def group_by_product(usages)
      usages.each_with_index.sort_by do |usage, index|
        rate_card = usage.contract_rate_card.rate_card
        [rate_card.product.code, rate_card.product_filter_id.nil? ? 0 : 1, index]
      end.map(&:first)
    end
  end
end
