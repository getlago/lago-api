# frozen_string_literal: true

class BillRecurringPayInAdvanceChargesJob < ApplicationJob
  queue_as 'billing'

  def perform(subscriptions, timestamp)
    Fees::CreateRecurringPayInAdvanceService.call(subscriptions:, billing_at: Time.zone.at(timestamp))
  end
end
