# frozen_string_literal: true

module Clock
  class CancelAbandonedPaymentsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Payment.abandoned_at_authentication.find_each do |payment|
        Invoices::Payments::CancelAbandonedJob.perform_later(payment)
      end
    end
  end
end
