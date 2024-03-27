# frozen_string_literal: true

module Invoices
  class RefreshDraftJob < ApplicationJob
    queue_as "invoices"

    def perform(invoice)
      ::Invoices::RefreshDraftService.call(invoice:)
    end
  end
end
