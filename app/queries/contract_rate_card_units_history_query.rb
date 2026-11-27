# frozen_string_literal: true

class ContractRateCardUnitsHistoryQuery < BaseQuery
  Result = BaseResult[:histories]

  def initialize(organization:, contract_rate_cards:)
    @contract_rate_cards = contract_rate_cards
    super(organization:)
  end

  def call
    cards = contract_rate_cards.select { |card| card.organization_id == organization.id }
    preload_associations(cards)
    changes = changes_by_card(cards)

    result.histories = cards.to_h do |card|
      [card.id, build_history(card, changes.fetch(card.id, []))]
    end
    result
  end

  private

  attr_reader :contract_rate_cards

  def preload_associations(cards)
    ActiveRecord::Associations::Preloader.new(records: cards, associations: [:terms, {contract: :customer}]).call
    preload_billing_entities(cards)
    preload_schedule_inputs(cards)
  end

  def preload_billing_entities(cards)
    customers = cards.filter_map { |card| card.contract.customer if card.terms.any? }
    customers.select! { |customer| customer.timezone.blank? }
    ActiveRecord::Associations::Preloader.new(records: customers.uniq, associations: :billing_entity).call
  end

  def preload_schedule_inputs(cards)
    scheduled_cards = cards.select { |card| card.terms.any?(&:next_billing_cycle?) }
    ActiveRecord::Associations::Preloader.new(
      records: scheduled_cards,
      associations: [{rate_phases: :rate_override}, {rate_card: [:rates, :product]}]
    ).call
  end

  def build_history(card, changes)
    units_changes = changes.map { |_, timestamp, units| [timestamp, units] }
    ContractRateCards::UnitsHistory.new(terms: card.terms, changes: units_changes, schedule: schedule_for(card))
  end

  def schedule_for(card)
    return unless card.terms.any?(&:next_billing_cycle?)

    Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
  end

  def changes_by_card(cards)
    ids = cards.filter_map(&:id)
    return {} if ids.empty?

    BillingOperation.units_changes.where(organization:, contract_rate_card_id: ids)
      .order(:contract_rate_card_id, :billing_at)
      .pluck(:contract_rate_card_id, :billing_at, :units_after)
      .group_by(&:first)
  end
end
