# frozen_string_literal: true

module Invoices
  module Payments
    class CreateSyncService < CreateService
      def call
        case payment_provider
        when :stripe
          Invoices::Payments::StripeCreateJob.perform_now(invoice)
        when :gocardless
          Invoices::Payments::GocardlessCreateJob.perform_now(invoice)
        when :adyen
          Invoices::Payments::AdyenCreateJob.perform_now(invoice)
        when :pinet
          Invoices::Payments::PinetCreateJob.perform_now(invoice)
        end
      end
    end
  end
end
