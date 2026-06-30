# frozen_string_literal: true

module RateCardRates
  class DestroyService < BaseService
    Result = BaseResult[:rate_card_rate]

    def initialize(rate_card_rate:)
      @rate_card_rate = rate_card_rate
      super
    end

    activity_loggable(
      action: "rate_card.updated",
      record: -> { rate_card_rate&.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "rate_card_rate") unless rate_card_rate

      # Active and terminated rates are kept for audit: the timeline only moves
      # forward by appending new rates.
      unless rate_card_rate.pending?
        return result.single_validation_failure!(field: :status, error_code: "only_pending_rates_can_be_deleted")
      end

      rate_card_rate.discard!

      result.rate_card_rate = rate_card_rate
      result
    end

    private

    attr_reader :rate_card_rate
  end
end
