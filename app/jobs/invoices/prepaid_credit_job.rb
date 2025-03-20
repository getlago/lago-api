# frozen_string_literal: true

module Invoices
  class PrepaidCreditJob < ApplicationJob
    queue_as "high_priority"

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6
    unique :until_executed, on_conflict: :log

    def perform(invoice, payment_status = :succeeded)  # Default to :succeeded for old jobs
      wallet_transaction = invoice.fees.find_by(fee_type: "credit")&.invoiceable

      if payment_status.to_sym == :succeeded
        Wallets::ApplyPaidCreditsService.call(wallet_transaction:)
        Invoices::FinalizeOpenCreditService.call(invoice:)
      elsif payment_status.to_sym == :failed
        WalletTransactions::MarkAsFailedService.new(wallet_transaction:).call
      end
    end
  end
end
