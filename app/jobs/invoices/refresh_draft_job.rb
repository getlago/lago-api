# frozen_string_literal: true

module Invoices
  class RefreshDraftJob < ApplicationJob
    queue_as 'invoices'

    unique :until_executed, on_conflict: :log

    def perform(invoice)
      ::Invoices::RefreshDraftService.call(invoice:)
    end
  end
end
