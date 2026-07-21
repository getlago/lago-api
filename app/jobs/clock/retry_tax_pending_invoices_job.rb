# frozen_string_literal: true

module Clock
  class RetryTaxPendingInvoicesJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      Invoice
        .pending
        .tax_pending
        .find_each do |invoice|
          Invoices::ProviderTaxes::PullTaxesAndApplyJob.perform_later(invoice:)
        end
    end
  end
end
