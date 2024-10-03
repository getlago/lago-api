# frozen_string_literal: true

module Invoices
  class RefreshDraftJob < ApplicationJob
    queue_as 'invoices'

    unique :until_executed, on_conflict: :log, lock_ttl: 6.hours

    def perform(invoice)
      # if this has already been set to false, we can skip the job
      return unless invoice.ready_to_be_refreshed?

      ::Invoices::RefreshDraftService.call(invoice:)
    end
  end
end
