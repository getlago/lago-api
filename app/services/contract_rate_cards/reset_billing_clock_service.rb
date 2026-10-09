# frozen_string_literal: true

module ContractRateCards
  # Sets a card's clock to the billing date its current schedule gives the
  # period around the timestamp. Built from the stored lifecycle and phases, so
  # a card whose schedule cannot be built, or has run out, keeps its clock.
  class ResetBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:, timestamp: Time.current)
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      super
    end

    def call
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card:)
      next_billing_at = build.schedule.billing_at_covering(timestamp) if build.success?

      contract_rate_card.update!(next_billing_at:) if next_billing_at

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :timestamp
  end
end
