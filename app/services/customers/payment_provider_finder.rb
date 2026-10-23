# frozen_string_literal: true

module Customers
  module PaymentProviderFinder
    extend ActiveSupport::Concern

    PROVIDER_CONFIGURATION_ERRORS = %w[payment_provider_not_found payment_provider_code_missing].freeze

    included do
      def payment_provider(customer)
        payment_provider_result = PaymentProviders::FindService.new(
          organization_id: customer.organization_id,
          code: customer.payment_provider_code,
          payment_provider_type: customer.payment_provider
        ).call

        return nil if payment_provider_result.error&.code == "payment_provider_not_found"

        payment_provider_result.raise_if_error!
        payment_provider_result.payment_provider
      end

      def payment_provider_customer(payment)
        return nil unless payment

        PaymentProviderCustomers::BaseCustomer.with_discarded.find_by(id: payment.payment_provider_customer_id)
      end

      private

      def required_payment_provider(customer)
        lookup = PaymentProviders::FindService.call(
          organization_id: customer.organization_id,
          code: customer.payment_provider_code,
          payment_provider_type: customer.payment_provider
        )

        error = lookup.error
        if error.is_a?(BaseService::ServiceFailure) && PROVIDER_CONFIGURATION_ERRORS.include?(error.code)
          result.single_validation_failure!(error_code: error.code).raise_if_error!
        end

        lookup.raise_if_error!.payment_provider
      end
    end
  end
end
