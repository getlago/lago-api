# frozen_string_literal: true

module Customers
  class UpdateInvoiceGracePeriodService < BaseService
    def initialize(customer:, grace_period:)
      @customer = customer
      @grace_period = grace_period
      super
    end

    def call
      old_grace_period = customer.invoice_grace_period
      old_applicable_grace_period = customer.applicable_invoice_grace_period.to_i

      if grace_period != old_grace_period
        customer.invoice_grace_period = grace_period
        customer.save!

        grace_period_diff = customer.applicable_invoice_grace_period.to_i - old_applicable_grace_period

        # NOTE: Update issuing_date on draft invoices.
        customer.invoices.draft.find_each do |invoice|
          invoice.issuing_date = invoice.issuing_date + grace_period_diff.days
          invoice.payment_due_date = grace_period_payment_due_date(invoice)
          invoice.save!
        end

        customer.invoices.ready_to_be_finalized.find_each do |invoice|
          Invoices::FinalizeJob.perform_later(invoice)
        end
      end

      result.customer = customer
      result
    end

    private

    attr_reader :customer, :grace_period

    def grace_period_payment_due_date(invoice)
      invoice.issuing_date + customer.applicable_net_payment_term.days
    end
  end
end
