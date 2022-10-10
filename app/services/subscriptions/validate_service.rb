# frozen_string_literal: true

module Subscriptions
  class ValidateService < BaseValidator
    def valid?
      return false unless valid_customer?
      return false unless valid_plan?

      valid_subscription_date?

      if errors?
        result.validation_failure!(errors: errors)
        return false
      end

      true
    end

    private

    def valid_customer?
      return true if args[:customer]

      result.not_found_failure!(resource: 'customer')

      false
    end

    def valid_plan?
      return true if args[:plan]

      result.not_found_failure!(resource: 'plan')

      false
    end

    def valid_subscription_date?
      return true if args[:subscription_date].is_a?(Date)
      return true if args[:subscription_date].is_a?(String) && Date._strptime(args[:subscription_date]).present?

      add_error(field: :subscription_date, error_code: 'invalid_date')

      false
    end
  end
end
