# frozen_string_literal: true

module Invoices
  module Payments
    class GeneratePaymentUrlService < BaseService
      def initialize(invoice:)
        @invoice = invoice
        @provider = invoice&.customer&.payment_provider&.to_s

        super
      end

      def call
        return result.not_found_failure!(resource: 'invoice') if invoice.blank?
        return result.single_validation_failure!(error_code: 'no_linked_payment_provider') unless provider
        return result.single_validation_failure!(error_code: 'invalid_payment_provider') if provider == 'gocardless'

        if invoice.succeeded? || invoice.voided? || invoice.draft?
          return result.single_validation_failure!(error_code: 'invalid_invoice_status_or_payment_status')
        end

        payment_url_result = Invoices::Payments::PaymentProviders::Factory.new_instance(invoice:).generate_payment_url

        return payment_url_result unless payment_url_result.success?

        if payment_url_result.payment_url.blank?
          return result.single_validation_failure!(error_code: 'payment_provider_error')
        end

        payment_url_result
      end

      private

      attr_reader :invoice, :provider
    end
  end
end
