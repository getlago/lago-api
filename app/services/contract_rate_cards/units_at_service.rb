# frozen_string_literal: true

module ContractRateCards
  class UnitsAtService < BaseService
    Result = BaseResult[:units]

    def initialize(contract_rate_card:, timestamp:)
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      super
    end

    def call
      term = contract_rate_card.terms.select { it.starts_at <= timestamp }
        .max_by { [it.starts_at, it.created_at, it.id] }
      result.units = term&.units
      result
    end

    private

    attr_reader :contract_rate_card, :timestamp
  end
end
