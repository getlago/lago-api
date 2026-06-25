# frozen_string_literal: true

module Invoices
  # Removes an invoice document from the Meilisearch index.
  # No-op when Meilisearch is not configured.
  class RemoveFromSearchIndexService < BaseService
    Result = BaseResult

    def initialize(invoice_id:)
      @invoice_id = invoice_id
      super
    end

    def call
      return result unless MeilisearchClient.enabled?

      MeilisearchClient.invoices_index.delete_document(invoice_id)
      result
    end

    private

    attr_reader :invoice_id
  end
end
