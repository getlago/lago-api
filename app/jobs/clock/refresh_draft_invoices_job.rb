# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ApplicationJob
    include SentryCronConcern
    BATCH_SIZE = 1000

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    def perform
      Invoice.draft.ready_to_be_refreshed.with_active_subscriptions.includes(:credit_notes).find_in_batches(batch_size: BATCH_SIZE) do |invoices|
        invoices.each do |invoice|
          Invoices::RefreshDraftJob.perform_later(invoice)
        end
      end
    end
  end
end
