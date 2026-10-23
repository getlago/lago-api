# frozen_string_literal: true

module V2
  module Invoices
    class PaymentDisputeLostSerializer < ModelSerializer
      def serialize
        result = {invoice:}
        result[:provider_error] = options[:provider_error] if options[:provider_error].present?
        result
      end

      private

      def invoice
        ::V2::InvoiceSerializer.new(model, includes: ::V2::InvoiceSerializer::WEBHOOK_INCLUDES).serialize
      end
    end
  end
end
