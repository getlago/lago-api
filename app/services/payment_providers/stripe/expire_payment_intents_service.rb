# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class ExpirePaymentIntentsService < BaseService
      Result = BaseResult

      def call
        active_payment_intents.find_each do |payment_intent|
          PaymentIntents::ExpireService.call!(invoice: payment_intent.invoice)
        end

        result
      end

      private

      # NOTE: a customer has a single payment connection today, so this exactly
      #       targets the connection whose setting changed. When multi-connection
      #       (multi_connection) lands, re-scope to the invoice's snapshotted payment
      #       connection (invoices.payment_provider_customer_id) — the customer will no
      #       longer identify a single connection.
      def active_payment_intents
        PaymentIntent
          .active
          .joins(invoice: :customer)
          .where(customers: {id: payment_provider.customers.select(:id)})
      end
    end
  end
end
