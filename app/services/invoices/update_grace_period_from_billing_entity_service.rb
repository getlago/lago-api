# frozen_string_literal: true

module Invoices
  class UpdateGracePeriodFromBillingEntityService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, old_grace_period:)
      @invoice = invoice
      @old_grace_period = old_grace_period
      super
    end

    def call
      result.invoice = invoice
      # only update issuing_date when there is no override on customer
      return result if invoice.customer.invoice_grace_period.present?
      return result if !invoice.draft?

      new_grace_period = invoice.billing_entity.invoice_grace_period
      # Idempotency! if the applied_grace_period is already the same, we should not update the dates
      return result if invoice.applied_grace_period == new_grace_period

      grace_period_diff = new_grace_period - old_grace_period

      invoice.issuing_date = invoice.issuing_date + grace_period_diff.days
      invoice.applied_grace_period = new_grace_period
      invoice.payment_due_date = invoice.issuing_date + invoice.customer.applicable_net_payment_term.days
      invoice.save!

      result
    end

    private

    attr_reader :invoice, :old_grace_period
  end
end
