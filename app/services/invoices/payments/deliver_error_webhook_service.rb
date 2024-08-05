# frozen_string_literal: true

module Invoices
  module Payments
    class DeliverErrorWebhookService < BaseService
      def initialize(invoice, params)
        @invoice = invoice
        @params = params
      end

      def call_async
        if invoice.open? && invoice.credit?
          wallet_transaction = invoice.fees.credit.first.invoiceable
          SendWebhookJob.perform_later('wallet_transaction.payment_failure', wallet_transaction, params)
        elsif invoice.visible?
          SendWebhookJob.perform_later('invoice.payment_failure', invoice, params)
        end

        result
      end

      private

      attr_reader :invoice, :params
    end
  end
end
