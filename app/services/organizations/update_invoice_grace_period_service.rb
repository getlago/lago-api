# frozen_string_literal: true

module Organizations
  class UpdateInvoiceGracePeriodService < BaseService
    def initialize(organization:, grace_period:)
      @organization = organization
      @grace_period = grace_period.to_i
      super
    end

    def call
      old_grace_period = organization.invoice_grace_period.to_i
      grace_period_diff = grace_period - old_grace_period

      if grace_period != old_grace_period
        organization.invoice_grace_period = grace_period
        organization.save!

        # NOTE: Update issuing_date on draft invoices.
        organization.invoices.draft.each do |invoice|
          invoice.issuing_date = invoice.issuing_date + grace_period_diff.days
          invoice.payment_due_date = grace_period_payment_due_date(invoice)
          invoice.save!
        end

        # NOTE: Finalize related draft invoices.
        organization.invoices.ready_to_be_finalized.each do |invoice|
          Invoices::RefreshDraftAndFinalizeService.call(invoice:)
        end
      end

      result.organization = organization
      result
    end

    private

    attr_reader :organization, :grace_period

    def grace_period_payment_due_date(invoice)
      invoice.issuing_date + invoice.customer.applicable_net_payment_term.days
    end
  end
end
