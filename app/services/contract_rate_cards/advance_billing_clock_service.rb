# frozen_string_literal: true

module ContractRateCards
  # Moves a card's billing clock to the next instant its schedule falls due.
  class AdvanceBillingClockService < BaseService
    Result = BaseResult

    def initialize(contract_rate_card:, schedule:, timestamp:)
      @contract_rate_card = contract_rate_card
      @schedule = schedule
      @timestamp = timestamp
      super
    end

    def call
      advance_to = schedule.next_billing_at(after: timestamp)
      clock = contract_rate_card.next_billing_at

      # Exhausted, or never set, or later: what it must never do is move back.
      if advance_to.nil? || clock.nil? || advance_to > clock
        contract_rate_card.update!(next_billing_at: advance_to)
      end

      result
    end

    private

    attr_reader :contract_rate_card, :schedule, :timestamp
  end
end
