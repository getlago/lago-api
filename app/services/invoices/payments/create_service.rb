# frozen_string_literal: true

module Invoices
  module Payments
    class CreateService < BaseService
      def initialize(invoice:, payment_provider: nil)
        @invoice = invoice
        @payment_provider = payment_provider&.to_sym

        super
      end

      def call
        # TODO: Refactor to avoid duplicated logic in provider services.
        #       Lago Payment related logic should be handled here and the
        #       payment execution should be delegated to the provider services

        case payment_provider
        when :stripe
          Invoices::Payments::StripeService.call(invoice)
        when :gocardless
          Invoices::Payments::GocardlessService.call(invoice)
        when :adyen
          Invoices::Payments::AdyenService.call(invoice)
        end
      end

      def call_async
        return result unless payment_provider

        Invoices::Payments::CreateJob.perform_later(invoice:, payment_provider:)

        result.payment_provider = payment_provider
        result
      end


      private

      attr_reader :invoice

      def payment_provider
        @payment_provider ||= invoice.customer.payment_provider&.to_sym
      end
    end
  end
end
