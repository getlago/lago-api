# frozen_string_literal: true

module Clock
  class CancelAbandonedPaymentsJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 100
    SPACING = 1.minute

    def perform
      candidates.find_in_batches(batch_size: BATCH_SIZE).with_index do |payments, index|
        payments.each do |payment|
          Invoices::Payments::CancelAbandonedJob
            .set(wait: index * SPACING)
            .perform_later(payment)
        end
      end
    end

    private

    def candidates
      Payment
        .payment_type_provider
        .joins(:payment_provider)
        .where(payable_payment_status: :processing, status: "requires_action")
        .where(updated_at: ..Invoices::Payments::CancelAbandonedService::ABANDONED_PERIOD.ago)
    end
  end
end
