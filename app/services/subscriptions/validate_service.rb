# frozen_string_literal: true

module Subscriptions
  class ValidateService < BaseValidator
    def valid?
      return false unless valid_customer?
      return false unless valid_plan?

      valid_subscription_at?
      valid_ending_at?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_customer?
      return true if args[:customer]

      result.not_found_failure!(resource: "customer")

      false
    end

    def valid_plan?
      return true if args[:plan]

      result.not_found_failure!(resource: "plan")

      false
    end

    def valid_subscription_at?
      return true if Utils::DatetimeService.valid_format?(args[:subscription_at])

      add_error(field: :subscription_at, error_code: "invalid_date")

      false
    end

    def valid_ending_at?
      return true if args[:ending_at].blank?

      if Utils::DatetimeService.valid_format?(args[:ending_at]) &&
          Utils::DatetimeService.valid_format?(args[:subscription_at]) &&
          ending_at.to_date > Time.current.to_date &&
          ending_at.to_date > subscription_at.to_date
        return true
      end

      add_error(field: :ending_at, error_code: "invalid_date")

      false
    end

    def ending_at
      @ending_at ||= if args[:ending_at].is_a?(String)
        DateTime.strptime(args[:ending_at])
      else
        args[:ending_at]
      end
    end

    def subscription_at
      @subscription_at ||= if args[:subscription_at].is_a?(String)
        DateTime.strptime(args[:subscription_at])
      else
        args[:subscription_at]
      end
    end
  end
end
