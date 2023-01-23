# frozen_string_literal: true

module Invoices
  class RefreshBatchJob < ApplicationJob
    queue_as 'invoices'

    def perform(invoice_ids)
      Invoice.find(invoice_ids).each do |invoice|
        ::Invoices::RefreshDraftService.call(invoice:)
      end
    end
  end
end
