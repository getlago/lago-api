# frozen_string_literal: true

module RateCardRates
  class CreateService < BaseService
    Result = BaseResult[:rate_card_rate]

    def initialize(rate_card:, params:, emit_activity_log: true, emit_events: true)
      @rate_card = rate_card
      @params = params.to_h.with_indifferent_access
      @emit_events = emit_activity_log && emit_events
      super
    end

    activity_loggable(
      action: "rate_card_rate.created",
      record: -> { result.rate_card_rate },
      condition: -> { emit_events }
    )

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      if Utils::Datetime.before_today?(params[:effective_from], timezone: rate_card.organization.timezone)
        return result.single_validation_failure!(field: :effective_from, error_code: "must_not_be_before_today")
      end

      normalized = ::RateProperties::NormalizeRangesService.call(rate_properties: params[:rate_properties])
      return result.fail_with_error!(normalized.error) if normalized.failure?

      ActiveRecord::Base.transaction do
        rate = rate_card.rates.create!(
          organization_id: rate_card.organization_id,
          code: params[:code].presence,
          effective_from: params[:effective_from],
          rate_model: params[:rate_model],
          rate_properties: normalized.rate_properties,
          min_amount_cents: params[:min_amount_cents] || 0,
          billing_interval_count: params[:billing_interval_count] || 1,
          billing_interval_unit: params[:billing_interval_unit],
          applied_pricing_unit_conversion_rate: params[:applied_pricing_unit_conversion_rate]
        )

        result.rate_card_rate = rate
        if emit_events
          SendWebhookJob.perform_after_commit("rate_card_rate.created", rate)
        end
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :params, :emit_events
  end
end
