# frozen_string_literal: true

module RateOverrides
  class CreateService < BaseService
    Result = BaseResult[:rate_override]

    # Structural card fields are inherited, never overridden. A caller naming
    # one has misunderstood the contract, not made a typo — reject it.
    NOT_OVERRIDABLE_FIELDS = %i[
      billing_timing currency proration display_on_invoice
      regroup_paid_fees wallet_targetable applied_pricing_unit_code
    ].freeze

    def initialize(rate_card:, params:)
      @rate_card = rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      structural_field = NOT_OVERRIDABLE_FIELDS.find { params.key?(it) }
      if structural_field
        return result.single_validation_failure!(field: structural_field, error_code: "not_overridable")
      end

      if rate_card.applied_pricing_unit_code.present? && params[:pricing_unit_conversion_rate].blank?
        return result.single_validation_failure!(field: :pricing_unit_conversion_rate, error_code: "value_is_mandatory")
      end

      # Overrides replace a rate on the same card, so they obey the same
      # model/item/timing compatibility matrix as catalog rates.
      compatibility_error = RateCardRates::ModelCompatibility.error_code(rate_model: params[:rate_model], rate_card:)
      if compatibility_error
        return result.single_validation_failure!(field: :rate_model, error_code: compatibility_error)
      end

      # Same rule as RateCardRate#validate_min_amount_timing: a spend floor
      # true-ups against a closed period, so it only exists on arrears cards.
      if params[:min_amount_cents].to_i.positive? && rate_card.advance?
        return result.single_validation_failure!(field: :min_amount_cents, error_code: "not_allowed_for_billing_timing")
      end

      rate_override = RateOverride.new(
        organization: rate_card.organization,
        rate_model: params[:rate_model],
        rate_properties: params[:rate_properties] || {},
        min_amount_cents: params[:min_amount_cents] || 0,
        billing_interval_count: params[:billing_interval_count],
        billing_interval_unit: params[:billing_interval_unit],
        pricing_unit_conversion_rate: params[:pricing_unit_conversion_rate]
      )
      rate_override.billable_metric = rate_card.product.billable_metric
      rate_override.save!

      result.rate_override = rate_override
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :params
  end
end
