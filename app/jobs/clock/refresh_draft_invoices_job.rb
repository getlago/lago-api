# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    limits_concurrency to: 1, key: 'refresh_draft_invoices', duration: 5.minutes

    def perform
      Invoice.ready_to_be_refreshed.with_active_subscriptions.find_each do |invoice|
        Invoices::RefreshDraftJob.perform_later(invoice)
      end
    end
  end
end
