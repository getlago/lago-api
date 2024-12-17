# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    include SentryCronConcern
    BATCH_SIZE = 500

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    def perform
      Invoice.ready_to_be_finalized.includes(:credit_notes).find_in_batches(batch_size: BATCH_SIZE) do |invoices|
        invoices.each do |invoice|
          Invoices::FinalizeJob.perform_later(invoice)
        end
      end
    end
  end
end
