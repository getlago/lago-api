# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  def perform(subscription, timestamp)
    # TODO
    # Search all charges and linked BM to process
    # Create fees for each charges
    # Create a fee for the plan
    # Create the invoice
  end
end
