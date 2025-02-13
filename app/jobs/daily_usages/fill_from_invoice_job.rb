# frozen_string_literal: true

module DailyUsages
  class FillFromInvoiceJob < ApplicationJob
    queue_as "low_priority"

    def perform(invoice:, subscriptions:)
      DailyUsages::FillFromInvoiceService.call(invoice:, subscriptions:).raise_if_error!
    end
  end
end
