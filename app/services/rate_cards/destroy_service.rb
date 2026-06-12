# frozen_string_literal: true

module RateCards
  class DestroyService < BaseService
    Result = BaseResult[:rate_card]

    def initialize(rate_card:)
      @rate_card = rate_card
      super
    end

    activity_loggable(
      action: "rate_card.deleted",
      record: -> { result.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      ActiveRecord::Base.transaction do
        rate_card.rates.discard_all!
        rate_card.discard!
      end

      result.rate_card = rate_card
      result
    end

    private

    attr_reader :rate_card
  end
end
