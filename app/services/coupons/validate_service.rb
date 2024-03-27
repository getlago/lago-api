# frozen_string_literal: true

module Coupons
  class ValidateService < BaseValidator
    def valid?
      valid_expiration_at?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_expiration_at?
      return true if args[:expiration_at].blank?

      expiration_at = if args[:expiration_at].is_a?(Time)
        args[:expiration_at]
      elsif args[:expiration_at].is_a?(String) && Date._strptime(args[:expiration_at]).present?
        Date.strptime(args[:expiration_at])
      end

      return true if expiration_at && expiration_at.to_date >= Time.current.to_date

      add_error(field: :expiration_at, error_code: "invalid_date")

      false
    end
  end
end
