# frozen_string_literal: true

module Invoices
  module Payments
    class CreateService < BaseService
      def initialize(invoice)
        @invoice = invoice

        super
      end

      def call
        case payment_provider
        when :stripe
          Invoices::Payments::StripeCreateJob.perform_later(invoice)
        when :gocardless
          Invoices::Payments::GocardlessCreateJob.perform_later(invoice)
        when :adyen
          Invoices::Payments::AdyenCreateJob.perform_later(invoice)
        end
      rescue ActiveJob::Uniqueness::JobNotUnique => e
        Sentry.capture_exception(e)
      end

      private

      attr_reader :invoice

      def payment_provider
        invoice.customer.payment_provider&.to_sym
      end
    end
  end
end
