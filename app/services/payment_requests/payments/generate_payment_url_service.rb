# frozen_string_literal: true

module PaymentRequests
  module Payments
    class GeneratePaymentUrlService < BaseService
      PROVIDER_GOCARDLESS = "gocardless"

      def initialize(payable:)
        @payable = payable
        @provider = payable.customer.payment_provider.to_s

        super
      end

      def call
        return result.single_validation_failure!(error_code: "no_linked_payment_provider") if provider.blank?
        return result.single_validation_failure!(error_code: "invalid_payment_provider") if gocardless_provider?
        return result.single_validation_failure!(error_code: "invalid_payment_status") if payable.payment_succeeded?

        payment_url_result = PaymentRequests::Payments::PaymentProviders::Factory.new_instance(payable:).generate_payment_url

        return payment_url_result unless payment_url_result.success?

        return result.single_validation_failure!(error_code: "payment_provider_error") if payment_url_result.payment_url.blank?

        payment_url_result
      end

      private

      attr_reader :payable, :provider

      def gocardless_provider?
        provider == PROVIDER_GOCARDLESS
      end
    end
  end
end
