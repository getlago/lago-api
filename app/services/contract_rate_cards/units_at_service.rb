# frozen_string_literal: true

module ContractRateCards
  class UnitsAtService < BaseService
    Result = BaseResult[:units, :scheduled_term, :units_by_timestamp]

    def initialize(contract_rate_card:, timestamp:, history: nil)
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      @history = history
      super
    end

    def call
      @history ||= ContractRateCardUnitsHistoryQuery.call!(organization: contract_rate_card.organization,
        contract_rate_cards: [contract_rate_card]).histories.fetch(contract_rate_card.id)
      result.units_by_timestamp = history.units_by_timestamp
      result.units = history.units_at(timestamp)
      result.scheduled_term = history.scheduled_term_at(timestamp)
      result
    end

    private

    attr_reader :contract_rate_card, :timestamp, :history
  end
end
