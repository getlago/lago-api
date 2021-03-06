# frozen_string_literal: true

class BillAddOnJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(subscription, applied_add_on, date)
    result = Invoices::AddOnService.new(
      subscription: subscription,
      applied_add_on: applied_add_on,
      date: date,
    ).create

    raise result.throw_error unless result.success?
  end
end
