# frozen_string_literal: true

module ContractRateCards
  # Starts a card's billing lifecycle from its contract: the card begins on the
  # contract's start day and keeps an anchor of its own or inherits the
  # contract's. On a contract that started in the past, the clock waits for the
  # billing date of the current period; the schedule still walks from the
  # card's start, so the periods before it are billed on that date.
  class SeedLifecycleService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:, billing_anchor_date: nil)
      @contract_rate_card = contract_rate_card
      @billing_anchor_date = billing_anchor_date
      super
    end

    def call
      contract_rate_card.update!(contract_rate_card.contract.default_rate_card_lifecycle(billing_anchor_date:))
      contract_rate_card.update!(next_billing_at: initial_next_billing_at)

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :billing_anchor_date

    # Built from the stored lifecycle and phases, so it runs once both are saved.
    def initial_next_billing_at
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card:)

      if build.success?
        # An ended schedule has no next date: the card keeps its start as clock.
        build.schedule.billing_at_covering(Time.current) || contract_rate_card.next_billing_at
      else
        contract_rate_card.next_billing_at
      end
    end
  end
end
