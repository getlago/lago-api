# frozen_string_literal: true

class ContractRateCardUnitsHistoryQuery < BaseQuery
  Result = BaseResult[:histories]

  def initialize(organization:, contract_rate_cards:)
    @contract_rate_cards = contract_rate_cards
    super(organization:)
  end

  def call
    cards = contract_rate_cards.select { it.organization_id == organization.id }
    ActiveRecord::Associations::Preloader.new(records: cards, associations: [:terms, {contract: :customer}]).call
    customers = cards.filter_map { it.contract.customer if it.terms.any? }.select { it.timezone.blank? }.uniq
    ActiveRecord::Associations::Preloader.new(records: customers, associations: :billing_entity).call
    changes = changes_by_card(cards)

    result.histories = cards.to_h do |card|
      values = changes.fetch(card.id, []).map { |_, timestamp, units| [timestamp, units] }
      [card.id, ContractRateCards::UnitsHistory.new(terms: card.terms, changes: values)]
    end
    result
  end

  private

  attr_reader :contract_rate_cards

  def changes_by_card(cards)
    ids = cards.filter_map(&:id)
    return {} if ids.empty?

    BillingOperation.where(organization:, contract_rate_card_id: ids, reason: "contract_units_change")
      .order(:contract_rate_card_id, :billing_at)
      .pluck(:contract_rate_card_id, :billing_at, :units_after)
      .group_by(&:first)
  end
end
