# frozen_string_literal: true

module Clock
  class MarkInvoicesAsPaymentOverdueJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Invoice
        .finalized
        .not_payment_succeeded
        .where(payment_overdue: false)
        .where(payment_dispute_lost_at: nil)
        .where(payment_due_date: ...Time.current)
        .find_in_batches do |invoices|
          jobs = invoices.map do |invoice|
            Invoices::Payments::MarkOverdueJob.new(invoice:)
          end
          ActiveJob.perform_all_later(jobs)
        end
    end
  end
end
