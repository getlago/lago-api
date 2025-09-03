# frozen_string_literal: true

module Subscriptions
  class ValidateService < BaseValidator
    def valid?
      return false unless valid_customer?
      return false unless valid_plan?

      valid_subscription_at?
      valid_ending_at?
      valid_on_termination_credit_note?
      valid_on_termination_invoice?

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
      return true if Utils::Datetime.valid_format?(args[:subscription_at])

      add_error(field: :subscription_at, error_code: "invalid_date")

      false
    end

    def valid_ending_at?
      return true if args[:ending_at].blank?

      if Utils::Datetime.valid_format?(args[:ending_at]) &&
          Utils::Datetime.valid_format?(args[:subscription_at]) &&
          ending_at.to_date > Time.current.to_date &&
          ending_at.to_date > subscription_at.to_date
        return true
      end

      add_error(field: :ending_at, error_code: "invalid_date")
      false
    end

    def valid_on_termination_credit_note?
      return true if args[:on_termination_credit_note].blank?

      return true if Subscription::ON_TERMINATION_CREDIT_NOTES.include?(args[:on_termination_credit_note].to_sym)

      add_error(field: :on_termination_credit_note, error_code: "invalid_value")
      false
    end

    def valid_on_termination_invoice?
      return true if args[:on_termination_invoice].blank?

      return true if Subscription::ON_TERMINATION_INVOICES.include?(args[:on_termination_invoice].to_sym)

      add_error(field: :on_termination_invoice, error_code: "invalid_value")
      false
    end

    def ending_at
      @ending_at ||= if args[:ending_at].is_a?(String)
        DateTime.iso8601(args[:ending_at])
      else
        args[:ending_at]
      end
    end

    def subscription_at
      @subscription_at ||= if args[:subscription_at].is_a?(String)
        DateTime.iso8601(args[:subscription_at])
      else
        args[:subscription_at]
      end
    end
  end
end
