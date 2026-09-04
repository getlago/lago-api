# frozen_string_literal: true

class ContractRateCardsQuery < BaseQuery
  Result = BaseResult[:contract_rate_cards]
  Filters = BaseFilters[:contract_id, :external_id]

  def call
    contract_rate_cards = base_scope
    contract_rate_cards = with_contract(contract_rate_cards) if filters.contract_id.present?
    contract_rate_cards = with_external_id(contract_rate_cards) if filters.external_id.present?
    contract_rate_cards = paginate(contract_rate_cards)
    contract_rate_cards = apply_consistent_ordering(contract_rate_cards)

    result.contract_rate_cards = contract_rate_cards
    result
  end

  private

  # current_and_scheduled only: the show endpoint and serializer resolve a
  # card by code through the same scope, so an ended card must not appear in
  # the list and then 404 when fetched.
  def base_scope
    ContractRateCard.where(organization:).current_and_scheduled
  end

  def with_contract(scope)
    scope.where(contract_id: filters.contract_id)
  end

  def with_external_id(scope)
    scope.joins(:contract).where(contracts: {external_id: filters.external_id})
  end
end
