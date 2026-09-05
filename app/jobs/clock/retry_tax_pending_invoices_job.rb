# frozen_string_literal: true

module Clock
  class RetryTaxPendingInvoicesJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    THRESHOLD = -> { 7.days.ago }

    def perform
      Invoice
        .pending
        .tax_pending
        .where("updated_at > ?", THRESHOLD.call)
        .find_each do |invoice|
          Invoices::ProviderTaxes::PullTaxesAndApplyJob.perform_later(invoice:)
        end
    end
  end
end
