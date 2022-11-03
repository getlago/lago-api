# frozen_string_literal: true

module V1
  module CreditNotes
    class PaymentProviderRefundErrorSerializer < ModelSerializer
      alias credit_note model

      def serialize
        {
          lago_credit_note_id: credit_note.id,
          lago_customer_id: credit_note.customer.id,
          external_customer_id: credit_note.customer.external_id,
          provider_customer_id: options[:provider_customer_id],
          payment_provider: credit_note.customer.payment_provider,
          provider_error: options[:provider_error],
        }
      end
    end
  end
end
