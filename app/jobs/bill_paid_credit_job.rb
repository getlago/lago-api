# frozen_string_literal: true

class BillPaidCreditJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(wallet_transaction, timestamp)
    result = Invoices::PaidCreditService.new(
      wallet_transaction: wallet_transaction,
      timestamp: timestamp,
    ).create

    raise result.throw_error unless result.success?
  end
end
