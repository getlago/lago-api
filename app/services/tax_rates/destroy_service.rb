# frozen_string_literal: true

module TaxRates
  class DestroyService < BaseService
    def initialize(tax_rate:)
      @tax_rate = tax_rate

      super
    end

    def call
      return result.not_found_failure!(resource: 'tax_rate') unless tax_rate

      # NOTE: we must retrieve the list of draft invoice before proceeding to destroy
      #       as we need the applied_tax_rate relation
      draft_invoice_ids

      tax_rate.destroy!

      Invoices::RefreshBatchJob.perform_later(draft_invoice_ids) if draft_invoice_ids.present?

      result.tax_rate = tax_rate
      result
    end

    private

    attr_reader :tax_rate

    def draft_invoice_ids
      @draft_invoice_ids ||= tax_rate.organization.invoices
        .where(customer_id: tax_rate.applicable_customers.select(:id))
        .draft
        .pluck(:id)
    end
  end
end
