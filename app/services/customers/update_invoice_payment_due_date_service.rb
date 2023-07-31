# frozen_string_literal: true

module Customers
  class UpdateInvoicePaymentDueDateService < BaseService
    def initialize(customer:, net_payment_term:)
      @customer = customer
      @net_payment_term = net_payment_term
      super
    end

    def call
      ActiveRecord::Base.transaction do
        # NOTE: Update payment_due_date if net_payment_term changed
        customer.invoices.draft.each do |invoice|
          if customer.net_payment_term != net_payment_term
            invoice.update!(payment_due_date: invoice_payment_due_date(invoice))
          end
        end

        result.customer = customer
        result
      end
    end

    private

    attr_reader :customer, :net_payment_term

    def invoice_payment_due_date(invoice)
      invoice.issuing_date + (net_payment_term || customer.applicable_net_payment_term).days
    end
  end
end
