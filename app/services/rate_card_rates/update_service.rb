# frozen_string_literal: true

module RateCardRates
  class UpdateService < BaseService
    Result = BaseResult[:rate_card_rate]

    # Per the editability matrix: a terminated rate is frozen, an active rate only
    # accepts new pricing values, a pending rate is fully editable.
    FROZEN_ON_ACTIVE = %i[effective_datetime rate_model min_amount_cents billing_interval_count billing_interval_unit].freeze

    def initialize(rate_card_rate:, params:)
      @rate_card_rate = rate_card_rate
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "rate_card.updated",
      record: -> { rate_card_rate&.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "rate_card_rate") unless rate_card_rate

      if rate_card_rate.terminated?
        return result.single_validation_failure!(field: :status, error_code: "terminated_rate_not_editable")
      end

      if rate_card_rate.active?
        frozen_field = FROZEN_ON_ACTIVE.find { params.key?(it) }
        if frozen_field
          return result.single_validation_failure!(field: frozen_field, error_code: "not_editable_on_active_rate")
        end
      end

      assign_attributes
      rate_card_rate.save!

      result.rate_card_rate = rate_card_rate
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card_rate, :params

    def assign_attributes
      rate_card_rate.effective_datetime = params[:effective_datetime] if params.key?(:effective_datetime)
      rate_card_rate.rate_model = params[:rate_model] if params.key?(:rate_model)
      rate_card_rate.rate_properties = params[:rate_properties] if params.key?(:rate_properties)
      rate_card_rate.min_amount_cents = params[:min_amount_cents] if params.key?(:min_amount_cents)
      rate_card_rate.billing_interval_count = params[:billing_interval_count] if params.key?(:billing_interval_count)
      rate_card_rate.billing_interval_unit = params[:billing_interval_unit] if params.key?(:billing_interval_unit)

      if params.key?(:applied_pricing_unit_conversion_rate)
        rate_card_rate.applied_pricing_unit_conversion_rate = params[:applied_pricing_unit_conversion_rate]
      end
    end
  end
end
