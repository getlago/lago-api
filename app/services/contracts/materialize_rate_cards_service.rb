# frozen_string_literal: true

module Contracts
  # Materializes the plan's rate cards onto the contract: one
  # contract_rate_card per plan_rate_card, carrying the billing lifecycle
  # (anchor, clock, units). Pricing is not copied — a plan is immutable once
  # it has contracts, so phases and rates resolve by reference through the
  # plan entry.
  class MaterializeRateCardsService < BaseService
    Result = BaseResult[:contract_rate_cards]

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result unless contract.plan

      materialized = []
      ActiveRecord::Base.transaction do
        contract.plan.applied_rate_cards.find_each do |plan_rate_card|
          materialized << contract.applied_rate_cards.create!(
            organization: contract.organization,
            rate_card: plan_rate_card.rate_card,
            units: plan_rate_card.units,
            **contract.default_rate_card_lifecycle
          )
        end
      end

      result.contract_rate_cards = materialized
      result
    end

    private

    attr_reader :contract
  end
end
