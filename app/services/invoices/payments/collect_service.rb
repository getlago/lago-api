# frozen_string_literal: true

module Invoices
  module Payments
    # Collects a finalized invoice: a regenerated advance_charges receipt records its manual payment,
    # any other invoice is charged through its payment provider.
    class CollectService < BaseService
      Result = BaseResult

      def initialize(invoice:, payment_method_params: {})
        @invoice = invoice
        @payment_method_params = payment_method_params
        super
      end

      def call
        if invoice.regenerated_advance_charges?
          Invoices::RecordAdvanceChargesPaymentService.call!(invoice:)
        else
          Invoices::Payments::CreateService.call_async(invoice:, payment_method_params:)
        end

        result
      end

      private

      attr_reader :invoice, :payment_method_params
    end
  end
end
