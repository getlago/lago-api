# frozen_string_literal: true

module ContractRateCards
  # Starts a card's billing lifecycle from its contract: the card begins on the
  # contract's start day and keeps an anchor of its own or inherits the
  # contract's. The cursor starts at the first priced obligation, including
  # overdue coverage when the contract starts in the past.
  class SeedLifecycleService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:, billing_anchor_date: nil)
      @contract_rate_card = contract_rate_card
      @billing_anchor_date = billing_anchor_date
      super
    end

    def call
      ActiveRecord::Base.transaction do
        previous_effective_date = contract_rate_card.effective_date
        contract_rate_card.update!(contract_rate_card.contract.default_rate_card_lifecycle(billing_anchor_date:))
        sync_initial_term_date(previous_effective_date) if previous_effective_date != contract_rate_card.effective_date
        ResetBillingClockService.call!(contract_rate_card:, timestamp: contract_rate_card.contract.started_at)
      end

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :contract_rate_card, :billing_anchor_date

    def sync_initial_term_date(previous_effective_date)
      term = contract_rate_card.terms.find_by(effective_date: previous_effective_date)
      term&.update!(effective_date: contract_rate_card.effective_date)
    end
  end
end
