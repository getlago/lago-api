# frozen_string_literal: true

module Taxes
  class DestroyService < BaseService
    def initialize(tax:)
      @tax = tax

      super
    end

    def call
      return result.not_found_failure!(resource: 'tax') unless tax

      # NOTE: we must retrieve the list of draft invoice before proceeding to destroy
      #       as we need the applied_tax relation
      draft_invoice_ids

      tax.destroy!

      Invoices::RefreshBatchJob.perform_later(draft_invoice_ids) if draft_invoice_ids.present?

      result.tax = tax
      result
    end

    private

    attr_reader :tax

    def draft_invoice_ids
      @draft_invoice_ids ||= tax.organization.invoices
        .where(customer_id: tax.applicable_customers.select(:id))
        .draft
        .pluck(:id)
    end
  end
end
