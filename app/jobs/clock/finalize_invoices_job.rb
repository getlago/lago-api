# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    queue_as 'clock'

    def perform
      Invoice.ready_to_be_finalized.each do |invoice|
        Invoices::FinalizeJob.perform_later(invoice)
      end
    end
  end
end
