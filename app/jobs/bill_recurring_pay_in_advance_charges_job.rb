# frozen_string_literal: true

class BillRecurringPayInAdvanceChargesJob < ApplicationJob
  queue_as 'billing'

  def perform(subscriptions, timestamp)
    Fees::CreateRecurringPayInAdvanceService.call(subscriptions:, billing_at: Time.zone.at(timestamp))

    # TODO: Should we retry the job if it fails?
    # result.raise_if_error!
  end
end
