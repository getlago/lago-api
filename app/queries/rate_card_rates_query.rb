# frozen_string_literal: true

class RateCardRatesQuery < BaseQuery
  Result = BaseResult[:rate_card_rates]
  Filters = BaseFilters[:rate_card_id]

  def call
    rate_card_rates = base_scope
    rate_card_rates = with_rate_card(rate_card_rates) if filters.rate_card_id.present?
    rate_card_rates = paginate(rate_card_rates)
    rate_card_rates = rate_card_rates.order(effective_from: :desc)

    result.rate_card_rates = rate_card_rates
    result
  end

  private

  # rate_card: :rates preloaded so each rate's status derives from the loaded
  # timeline instead of one query per row.
  def base_scope
    RateCardRate.where(organization:).includes(rate_card: :rates)
  end

  def with_rate_card(scope)
    scope.where(rate_card_id: filters.rate_card_id)
  end
end
