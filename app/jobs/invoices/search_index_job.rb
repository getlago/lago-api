# frozen_string_literal: true

module Invoices
  class SearchIndexJob < ApplicationJob
    queue_as :meilisearch

    def perform(invoice_id)
      invoice = Invoice.find_by(id: invoice_id)

      if invoice
        Invoices::Search::IndexService.call!(invoice:)
      else
        Invoices::Search::RemoveFromIndexService.call!(invoice_id:)
      end
    end
  end
end
