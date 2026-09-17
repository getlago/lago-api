# frozen_string_literal: true

module RateCardRates
  # v1-parity compatibility matrix between a rate model and the card pricing
  # it (product type, billing timing, proration). Returns the error code
  # to surface on :rate_model, or nil when the combination is billable.
  module ModelCompatibility
    # Mirrors FixedCharge::CHARGE_MODELS.
    FIXED_ITEM_RATE_MODELS = %w[standard graduated volume].freeze
    # Mirrors Charge#validate_prorated.
    PRORATION_ARREARS_MODELS = %w[standard volume graduated].freeze
    PRORATION_ADVANCE_MODELS = %w[standard].freeze

    module_function

    def error_code(rate_model:, rate_card:)
      item = rate_card&.product
      return nil unless rate_model && item

      if item.fixed? && !FIXED_ITEM_RATE_MODELS.include?(rate_model)
        return "not_allowed_for_product"
      end

      metric = item.billable_metric

      # Dynamic pricing only works on sum aggregation.
      if rate_model == "dynamic" && !metric&.sum_agg?
        return "not_allowed_for_aggregation_type"
      end

      # Percentage models price a monetary amount; a latest aggregation keeps
      # a point-in-time value, not an amount to take a percentage of.
      if %w[percentage graduated_percentage].include?(rate_model) && metric&.latest_agg?
        return "not_allowed_for_aggregation_type"
      end

      if rate_card.advance?
        # Volume needs the full period...
        return "not_allowed_for_billing_timing" if rate_model == "volume"
        # ...and advance billing needs an aggregation that can be priced per
        # event.
        return "not_allowed_for_aggregation_type" if metric && !metric.payable_in_advance?
      end

      if rate_card.proration
        return "not_allowed_with_proration" unless proration_models(rate_card, metric).include?(rate_model)
      end

      nil
    end

    def proration_models(rate_card, metric)
      # Usage proration needs a recurring, non-weighted metric; fixed items
      # prorate by calendar time and follow the same model lists.
      if metric
        return [] if metric.weighted_sum_agg? || !metric.recurring?
      end

      rate_card.advance? ? PRORATION_ADVANCE_MODELS : PRORATION_ARREARS_MODELS
    end
  end
end
