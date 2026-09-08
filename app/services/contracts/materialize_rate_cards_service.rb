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
      return result unless contract.catalog_plan

      materialized = []
      ActiveRecord::Base.transaction do
        contract.catalog_plan.applied_rate_cards.find_each do |plan_rate_card|
          card = contract.applied_rate_cards.new(
            organization: contract.organization,
            rate_card: plan_rate_card.rate_card,
            units: plan_rate_card.units,
            **contract.default_rate_card_lifecycle
          )
          card.next_billing_at = initial_next_billing_at(card, plan_rate_card)
          card.save!
          materialized << card
        end
      end

      result.contract_rate_cards = materialized
      result
    end

    private

    attr_reader :contract

    def initial_next_billing_at(card, plan_rate_card)
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card: card, plan_rate_card:)

      if build.success?
        # Backdated contracts join the current period; an ended schedule has no next date.
        build.schedule.billing_at_covering(Time.current) || card.next_billing_at
      else
        card.next_billing_at
      end
    end
  end
end
