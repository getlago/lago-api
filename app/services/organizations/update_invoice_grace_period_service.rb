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

        Invoices::UpdateAllInvoiceGracePeriodFromOrganizationJob.perform_later(organization:, old_grace_period:)
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
