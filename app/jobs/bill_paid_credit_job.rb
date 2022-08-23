# frozen_string_literal: true

class BillPaidCreditJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(customer, wallet_transaction, date)
    result = Invoices::PaidCreditService.new(
      customer: customer,
      wallet_transaction: wallet_transaction,
      date: date,
    ).create

    raise result.throw_error unless result.success?
  end
end
