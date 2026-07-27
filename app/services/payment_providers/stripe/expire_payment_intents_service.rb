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

      def active_payment_intents
        PaymentIntent
          .active
          .joins(invoice: :customer)
          .where(customers: {id: payment_provider.customers.select(:id)})
      end
    end
  end
end
