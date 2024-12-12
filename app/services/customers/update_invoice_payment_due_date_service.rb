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
        if net_payment_term != customer.applicable_net_payment_term
          customer.invoices.draft.each do |invoice|
            invoice.update!(net_payment_term:, payment_due_date: invoice_payment_due_date(invoice))
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
