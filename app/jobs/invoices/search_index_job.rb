# frozen_string_literal: true

module Invoices
  class SearchIndexJob < ApplicationJob
    queue_as :meilisearch

    retry_on Meilisearch::CommunicationError,
      Meilisearch::ApiError,
      Meilisearch::TimeoutError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT,
      HTTParty::UnsupportedURIScheme,
      Net::OpenTimeout,
      Net::ReadTimeout,
      EOFError, wait: :polynomially_longer, attempts: 3

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
