# frozen_string_literal: true

module Invoices
  class UpdateIssuingDateFromBillingEntityService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, old_issuing_date_settings:)
      @invoice = invoice
      @old_issuing_date_settings = old_issuing_date_settings
      super
    end

    def call
      result.invoice = invoice
      return result unless invoice.draft?

      invoice.issuing_date = invoice.issuing_date + issuing_date_adjustment.days
      invoice.applied_grace_period = invoice.customer.applicable_invoice_grace_period
      invoice.payment_due_date = invoice.issuing_date + invoice.customer.applicable_net_payment_term.days
      invoice.save!

      result
    end

    private

    attr_reader :invoice, :old_issuing_date_settings

    def issuing_date_adjustment
      recurring = invoice.invoice_subscriptions.first&.recurring?

      old_issuing_date_adjustment = Invoices::IssuingDateService.new(
        customer: invoice.customer,
        billing_entity: old_issuing_date_settings,
        recurring:
      ).issuing_date_adjustment

      new_issuing_date_adjustment = Invoices::IssuingDateService.new(
        customer: invoice.customer,
        billing_entity: invoice.billing_entity,
        recurring:
      ).issuing_date_adjustment

      new_issuing_date_adjustment - old_issuing_date_adjustment
    end
  end
end
