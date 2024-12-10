# frozen_string_literal: true

module Invoices
  module Payments
    class CreateService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice:, payment_provider: nil)
        @invoice = invoice
        @provider = payment_provider&.to_sym

        super
      end

      def call
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          Invoices::UpdateService.call!(
            invoice:,
            params: {payment_status: :succeeded, ready_for_payment_processing: false},
            webhook_notification: true
          )
          return result
        end

        # TODO(payments): Create a pending paymnent record with a DB uniqueness constraint on invoice_id
        #                 and inject it to the payment services to avoid duplicated payments
        ::PaymentProviders::CreatePaymentFactory.new_instance(provider:, invoice:).call
      end

      def call_async
        return result unless provider

        Invoices::Payments::CreateJob.perform_later(invoice:, payment_provider: provider)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :invoice

      delegate :customer, to: :invoice

      def provider
        @provider ||= invoice.customer.payment_provider&.to_sym
      end

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?

        payment_provider(customer).present?
      end
    end
  end
end
