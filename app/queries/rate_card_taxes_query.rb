# frozen_string_literal: true

class RateCardTaxesQuery < BaseQuery
  Result = BaseResult[:applied_taxes]
  Filters = BaseFilters[:rate_card_id]

  def call
    applied_taxes = base_scope
    applied_taxes = with_rate_card(applied_taxes) if filters.rate_card_id.present?

    result.applied_taxes = paginate(applied_taxes)
    result
  end

  private

  def base_scope
    RateCard::AppliedTax.where(organization:).listed
  end

  def with_rate_card(scope)
    scope.where(rate_card_id: filters.rate_card_id)
  end
end
