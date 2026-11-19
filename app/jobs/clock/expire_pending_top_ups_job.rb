# frozen_string_literal: true

module Clock
  class ExpirePendingTopUpsJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 100
    SPACING = 1.minute

    def perform
      candidates.find_in_batches(batch_size: BATCH_SIZE).with_index do |wallet_transactions, index|
        wallet_transactions.each do |wallet_transaction|
          WalletTransactions::ExpirePendingJob
            .set(wait: index * SPACING)
            .perform_later(wallet_transaction)
        end
      end
    end

    private

    # Matches index_wallet_transactions_pending_gated_top_ups. Only open invoices with nothing paid:
    # the others (generating, failed, finalized when the organization is not premium, or partly
    # paid by hand) never expire. Payments still moving are picked again every hour until they settle.
    def candidates
      WalletTransaction
        .inbound
        .pending
        .where(invoice_requires_successful_payment: true)
        .where(created_at: ..WalletTransactions::ExpirePendingService::TIMEOUT.ago)
        .joins(:invoice)
        .where(invoices: {status: :open, total_paid_amount_cents: 0})
    end
  end
end
