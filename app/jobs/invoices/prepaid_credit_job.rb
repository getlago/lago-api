# frozen_string_literal: true

module Invoices
  class PrepaidCreditJob < ApplicationJob
    queue_as 'wallets'

    unique :until_executed, on_conflict: :log

    def perform(invoice)
      wallet_transaction = invoice.fees.find_by(fee_type: 'credit')&.invoiceable
      Wallets::ApplyPaidCreditsService.call(wallet_transaction:)
      Invoices::FinalizeOpenCreditService.call(invoice:)
    end
  end
end
