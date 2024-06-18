# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ApplicationJob
    queue_as 'clock'

    def perform
      Invoice.ready_to_be_refreshed.find_each do |invoice|
        next unless invoice.subscriptions.pluck(:status).include?('active')

        Invoices::RefreshDraftJob.perform_later(invoice)
      end
    end
  end
end
