# frozen_string_literal: true

module Webhooks
  module PaymentProviders
    class InvoicePaymentFailureService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::PaymentProviders::InvoicePaymentErrorSerializer.new(
          object,
          root_name: object_type,
          options: options,
        )
      end

      def webhook_type
        'invoice.payment_failure'
      end

      def object_type
        'payment_provider_invoice_payment_error'
      end
    end
  end
end
