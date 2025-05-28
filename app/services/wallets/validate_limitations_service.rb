# frozen_string_literal: true

module Wallets
  class ValidateLimitationsService < BaseValidator
    def valid?
      return true unless args[:applies_to]

      valid_allowed_fee_types?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_allowed_fee_types?
      fee_types = args[:applies_to][:fee_types]

      return true if fee_types.blank?

      valid_types = Fee.fee_types.keys
      incoming = Array(fee_types).map(&:to_s)
      invalid = incoming - valid_types

      add_error(field: :allowed_fee_types, error_code: "invalid_fee_types") if invalid.any?
    end
  end
end
