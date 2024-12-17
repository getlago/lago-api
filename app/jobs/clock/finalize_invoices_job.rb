# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    def perform
      Invoice.ready_to_be_finalized.includes(:credit_notes).find_each do |invoice|
        Invoices::FinalizeJob.perform_later(invoice)
      end
    end
  end
end
