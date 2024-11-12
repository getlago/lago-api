# frozen_String_literal: true

module PaymentProviderCustomers
  module Stripe
    class UpdatePaymentMethodService < BaseService
      def initialize(stripe_customer:, payment_method_id:)
        @stripe_customer = stripe_customer
        @payment_method_id = payment_method_id

        super
      end

      def call
        return result.not_found_failure!(resource: 'stripe_customer') unless stripe_customer

        stripe_customer.payment_method_id = payment_method_id
        stripe_customer.save!

        reprocess_pending_invoices

        result.stripe_customer = stripe_customer
        result
      end

      private

      attr_reader :stripe_customer, :payment_method_id

      delegate :customer, to: :stripe_customer

      def reprocess_pending_invoices
        invoices = customer.invoices
          .payment_pending
          .where(ready_for_payment_processing: true)
          .where(status: 'finalized')

        invoices.find_each do |invoice|
          Invoices::Payments::StripeCreateJob.perform_later(invoice)
        end
      end
    end
  end
end
