# frozen_string_literal: true

module Subscriptions
  class ValidateService < BaseValidator
    def valid?
      valid_customer?
      valid_plan?
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

      add_error(field: :customer, error_code: 'customer_not_found')
    end

    def valid_plan?
      return true if args[:plan]

      add_error(field: :plan, error_code: 'plan_not_found')
    end

    def valid_subscription_date?
      return true if args[:subscription_date].nil?
      return true if args[:subscription_date].is_a?(Date)
      return true if args[:subscription_date].is_a?(String) && Date._strptime(args[:subscription_date]).present?

      add_error(field: :subscription_date, error_code: 'invalid_subscription_date')
    end
  end
end
