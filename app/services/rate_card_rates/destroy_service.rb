# frozen_string_literal: true

module RateCardRates
  class DestroyService < BaseService
    Result = BaseResult[:rate_card_rate]

    activity_loggable(
      action: "rate_card_rate.deleted",
      record: -> { rate_card_rate }
    )

    def initialize(rate_card_rate:)
      @rate_card_rate = rate_card_rate
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_card_rate") unless rate_card_rate

      # Active and terminated rates are kept for audit.
      unless rate_card_rate.pending?
        return result.single_validation_failure!(field: :status, error_code: "only_pending_rates_can_be_deleted")
      end

      ActiveRecord::Base.transaction do
        rate_card_rate.discard!
        SendWebhookJob.perform_after_commit("rate_card_rate.deleted", rate_card_rate)
      end

      result.rate_card_rate = rate_card_rate
      result
    end

    private

    attr_reader :rate_card_rate
  end
end
