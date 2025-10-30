# frozen_string_literal: true

module EInvoices
  module Payments
    module Common
      def credits_and_payments(&block)
        case payment.payment_type
        when Payment::PAYMENT_TYPES[:manual]
          yield EInvoices::BaseSerializer::STANDARD_PAYMENT, Money.new(payment.amount_cents)
        when Payment::PAYMENT_TYPES[:provider]
          yield EInvoices::BaseSerializer::CREDIT_CARD_PAYMENT, Money.new(payment.amount_cents)
        end
      end
    end
  end
end
