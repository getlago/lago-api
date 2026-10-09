# frozen_string_literal: true

module ContractRateCards
  # A contract can hold several versions of the card pricing the same product and product
  # filter, each taking over from its effective date. This picks, for each of them, the
  # version effective on the given date: the latest that started on or before it.
  class SelectEffectiveService < BaseService
    Result = BaseResult[:contract_rate_cards]

    def initialize(contract_rate_cards:, date:)
      @contract_rate_cards = contract_rate_cards
      @date = date
      super
    end

    def call
      result.contract_rate_cards = contract_rate_cards
        .group_by { |card| [card.contract_id, card.rate_card.product_id, card.rate_card.product_filter_id] }
        .filter_map { |_key, versions| effective_version(versions) }
      result
    end

    private

    attr_reader :contract_rate_cards, :date

    def effective_version(versions)
      ordered = versions.sort_by { |card| [card.effective_date, card.created_at, card.id] }
      first_later_index = ordered.bsearch_index { |card| card.effective_date > date } || ordered.length

      ordered[first_later_index - 1] unless first_later_index.zero?
    end
  end
end
