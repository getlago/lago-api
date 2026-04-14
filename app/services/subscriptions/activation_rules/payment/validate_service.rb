# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    module Payment
      class ValidateService < BaseValidator
        def valid?
          valid_timeout_hours?
          valid_payment_method?

          if errors?
            result.validation_failure!(errors:)
            return false
          end

          true
        end

        private

        def valid_timeout_hours?
          return true unless args[:rule].key?(:timeout_hours)
          return true if args[:rule][:timeout_hours].is_a?(Integer) && args[:rule][:timeout_hours] >= 0

          add_error(field: :timeout_hours, error_code: "value_must_be_positive_or_zero")
        end

        def valid_payment_method?
          return true if args[:payment_method].present? && args[:payment_method][:payment_method_type] == PaymentMethod::PAYMENT_METHOD_TYPES[:provider]
          return true if args[:payment_method].blank? && args[:subscription]&.payment_method_type == PaymentMethod::PAYMENT_METHOD_TYPES[:provider]
          return true if args[:payment_method].blank? && args[:subscription].nil? && args[:customer]&.payment_provider.present?

          return add_error(field: :payment_method, error_code: "no_linked_payment_provider") if args[:payment_method].blank? && args[:subscription].nil?
          add_error(field: :payment_method, error_code: "invalid_for_payment_activation_rules")
        end
      end
    end
  end
end
