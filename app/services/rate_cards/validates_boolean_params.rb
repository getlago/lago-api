# frozen_string_literal: true

module RateCards
  # Rails casts any non-falsey value to true on boolean columns; reject
  # non-boolean input from the permissive REST layer instead. nil is allowed.
  module ValidatesBooleanParams
    BOOLEAN_FIELDS = %i[proration display_on_invoice wallet_targetable].freeze

    private

    def boolean_params_failure
      invalid = BOOLEAN_FIELDS.select do |field|
        params.key?(field) && !params[field].nil? && ![true, false].include?(params[field])
      end
      return if invalid.empty?

      result.validation_failure!(errors: invalid.index_with { ["value_is_invalid"] })
    end
  end
end
