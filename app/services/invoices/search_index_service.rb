# frozen_string_literal: true

module Invoices
  # Upserts a single invoice into the Meilisearch index. The document is built
  # from the model's `meilisearch do … end` block. No-op when Meilisearch is off.
  class SearchIndexService < BaseService
    Result = BaseResult

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result unless MeilisearchClient.enabled?

      invoice.ms_index!
      result
    end

    private

    attr_reader :invoice
  end
end
