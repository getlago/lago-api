# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceFixedChargesJob < ApplicationJob
    queue_as "billing"

    def perform(subscription, timestamp)
      Invoices::CreatePayInAdvanceFixedChargesService.call!(
        subscription:,
        timestamp:
      )
    end
  end
end
