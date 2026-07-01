# frozen_string_literal: true

module Invoices
  # Removes an invoice document from the Meilisearch index by id (used when the
  # record no longer exists). No-op when Meilisearch is off.
  class RemoveFromSearchIndexService < BaseService
    Result = BaseResult

    def initialize(invoice_id:)
      @invoice_id = invoice_id
      super
    end

    def call
      return result unless MeilisearchClient.enabled?

      Invoice.index.delete_document(invoice_id)
      result
    end

    private

    attr_reader :invoice_id
  end
end
