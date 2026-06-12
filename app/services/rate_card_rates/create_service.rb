# frozen_string_literal: true

module RateCardRates
  class CreateService < BaseService
    Result = BaseResult[:rate_card_rate]

    def initialize(rate_card:, params:, emit_activity_log: true)
      @rate_card = rate_card
      @params = params.to_h.with_indifferent_access
      @emit_activity_log = emit_activity_log
      super
    end

    activity_loggable(
      action: "rate_card.updated",
      record: -> { rate_card },
      condition: -> { emit_activity_log }
    )

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      rate = rate_card.rates.create!(
        organization_id: rate_card.organization_id,
        effective_datetime: params[:effective_datetime],
        rate_model: params[:rate_model],
        rate_properties: params[:rate_properties] || {},
        min_amount_cents: params[:min_amount_cents] || 0,
        billing_interval_count: params[:billing_interval_count] || 1,
        billing_interval_unit: params[:billing_interval_unit],
        applied_pricing_unit_conversion_rate: params[:applied_pricing_unit_conversion_rate]
      )

      result.rate_card_rate = rate
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :params, :emit_activity_log
  end
end
