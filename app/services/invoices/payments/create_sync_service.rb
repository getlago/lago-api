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
          result = Invoices::Payments::PinetService.new(invoice:, is_sync: true).create
          result.raise_if_error!
        end
      end
    end
  end
end
