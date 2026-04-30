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
          return true if payment_provider? && payment_method_available?

          add_error(field: :payment_method, error_code: failure_error_code)
        end

        def payment_provider?
          return custom_payment_method_type_provider? if custom_payment_method?
          return subscription_payment_method_type_provider? if args[:subscription]

          customer_payment_provider?
        end

        def payment_method_available?
          return custom_payment_method_id? || customer&.default_payment_method.present? if custom_payment_method?
          return args[:subscription].payment_method_id.present? || customer&.default_payment_method.present? if args[:subscription]

          customer&.default_payment_method.present?
        end

        def failure_error_code
          return "customer_has_no_linked_payment_provider" if !custom_payment_method? && args[:subscription].nil? && !customer_payment_provider?
          return "customer_has_no_default_payment_method" if payment_provider?

          "manual_payment_method_invalid_for_payment_activation_rules"
        end

        def custom_payment_method?
          args[:payment_method].present?
        end

        def custom_payment_method_type_provider?
          args[:payment_method][:payment_method_type] == PaymentMethod::PAYMENT_METHOD_TYPES[:provider]
        end

        def custom_payment_method_id?
          custom_payment_method? && args[:payment_method][:payment_method_id].present?
        end

        def subscription_payment_method_type_provider?
          args[:subscription].payment_method_type == PaymentMethod::PAYMENT_METHOD_TYPES[:provider]
        end

        def customer_payment_provider?
          args[:customer]&.payment_provider.present?
        end

        def customer
          @customer ||= args[:customer] || args[:subscription]&.customer
        end
      end
    end
  end
end
