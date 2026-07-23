# frozen_string_literal: true

module RateOverrides
  class CreateService < BaseService
    Result = BaseResult[:rate_override]

    def initialize(rate_card:, params:)
      @rate_card = rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      if rate_card.applied_pricing_unit_code.present? && params[:pricing_unit_conversion_rate].blank?
        return result.single_validation_failure!(field: :pricing_unit_conversion_rate, error_code: "value_is_mandatory")
      end

      rate_override = RateOverride.create!(
        organization: rate_card.organization,
        rate_model: params[:rate_model],
        rate_properties: params[:rate_properties] || {},
        min_amount_cents: params[:min_amount_cents] || 0,
        billing_interval_count: params[:billing_interval_count],
        billing_interval_unit: params[:billing_interval_unit],
        pricing_unit_conversion_rate: params[:pricing_unit_conversion_rate]
      )

      result.rate_override = rate_override
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :params
  end
end
