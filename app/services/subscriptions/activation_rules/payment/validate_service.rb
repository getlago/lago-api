# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    module Payment
      class ValidateService < BaseValidator
        def valid?
          valid_timeout_hours?
          valid_payment_method?

          !errors?
        end

        private

        def valid_timeout_hours?
          return true unless args[:rule].key?(:timeout_hours)
          return true if args[:rule][:timeout_hours].is_a?(Integer) && args[:rule][:timeout_hours] >= 0

          add_error(field: :timeout_hours, error_code: "value_must_be_positive_or_zero")
        end

        def valid_payment_method?
          if args[:payment_method].present? && args[:payment_method][:payment_method_type] == PaymentMethod::PAYMENT_METHOD_TYPES[:manual]
            add_error(field: :payment_method, error_code: "invalid_for_activation_rules")
            return false
          end

          if args[:subscription]&.payment_method_type == PaymentMethod::PAYMENT_METHOD_TYPES[:manual]
            add_error(field: :payment_method, error_code: "invalid_for_activation_rules")
            return false
          end

          if args[:subscription].nil? && args[:payment_method].blank? && args[:customer]&.payment_provider.blank?
            add_error(field: :payment_method, error_code: "no_linked_payment_provider")
            return false
          end

          true
        end
      end
    end
  end
end
