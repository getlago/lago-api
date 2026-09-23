# frozen_string_literal: true

module Contracts
  # Materializes the plan's rate cards onto the contract: one
  # contract_rate_card per plan_rate_card, carrying the billing lifecycle
  # (anchor, clock, units) and a copy of the entry's phase timeline. A
  # contracted plan is locked, so the copy never drifts from it, and the
  # contract owns its phases from day one: they can be authored on the card
  # without reaching back into the plan.
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
        # Locked so a concurrent phase edit waits for this contract to commit
        # and then hits plan_locked, instead of landing a phase the copy missed.
        contract.catalog_plan.applied_rate_cards.lock.includes(rate_phases: :rate_override).find_each do |plan_rate_card|
          card = contract.applied_rate_cards.create!(
            organization: contract.organization,
            rate_card: plan_rate_card.rate_card,
            units: plan_rate_card.units,
            **contract.default_rate_card_lifecycle
          )
          copy_rate_phases(plan_rate_card, card)
          card.update!(next_billing_at: initial_next_billing_at(card))
          materialized << card
        end
      end

      result.contract_rate_cards = materialized
      result
    end

    private

    attr_reader :contract

    def copy_rate_phases(plan_rate_card, card)
      plan_rate_card.rate_phases.each do |phase|
        card.rate_phases.create!(
          organization: contract.organization,
          code: phase.code,
          position: phase.position,
          name: phase.name,
          billing_interval_cycle_count: phase.billing_interval_cycle_count,
          rate_override: copy_rate_override(phase.rate_override, card)
        )
      end
    end

    # A phase owns its override (unique index), so the copy gets its own row.
    def copy_rate_override(rate_override, card)
      return if rate_override.nil?

      copy = rate_override.dup
      copy.billable_metric = card.rate_card.product.billable_metric
      copy.save!
      copy
    end

    def initial_next_billing_at(card)
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card: card)

      if build.success?
        # Backdated contracts join the current period; an ended schedule has no next date.
        build.schedule.billing_at_covering(Time.current) || card.next_billing_at
      else
        card.next_billing_at
      end
    end
  end
end
