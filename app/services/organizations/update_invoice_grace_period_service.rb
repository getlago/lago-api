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

      if grace_period != old_grace_period
        organization.invoice_grace_period = grace_period
        organization.save!

        # NOTE: Update issuing_date on draft invoices.
        organization.invoices.draft.find_each do |invoice|
          grace_period_diff = invoice.customer.applicable_invoice_grace_period.to_i -
            old_applicable_grace_period(invoice.customer, old_grace_period)

          invoice.issuing_date = invoice.issuing_date + grace_period_diff.days
          invoice.payment_due_date = grace_period_payment_due_date(invoice)
          invoice.save!
        end

        organization.invoices.ready_to_be_finalized.find_each do |invoice|
          Invoices::FinalizeJob.perform_later(invoice)
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

    def old_applicable_grace_period(customer, old_org_grace_period)
      return customer.invoice_grace_period if customer.invoice_grace_period.present?

      old_org_grace_period
    end
  end
end
