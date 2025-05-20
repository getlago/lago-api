# frozen_string_literal: true

module Clock
  class MarkInvoicesAsPaymentOverdueJob < ClockJob
    def perform
      Invoice
        .finalized
        .not_payment_succeeded
        .where(payment_overdue: false)
        .where(payment_dispute_lost_at: nil)
        .where(payment_due_date: ...Time.current)
        .find_each do |invoice|
          Invoices::Payments::MarkOverdueService.call(invoice:)
        end
    end
  end
end
