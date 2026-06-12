# frozen_string_literal: true

module RateCards
  # Rails casts any non-falsey value to true on a boolean column, so a garbage
  # string like "hello" would silently become `true`. Reject non-boolean input
  # with a 422 instead. nil is allowed (missing key or explicit null falls back
  # to the column default). GraphQL is already protected by its Boolean arg type;
  # this guards the permissive JSON REST layer.
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
