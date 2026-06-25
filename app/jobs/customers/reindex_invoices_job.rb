# frozen_string_literal: true

module Customers
  # Re-indexes every invoice of a customer in Meilisearch. Used when denormalized
  # customer fields (name, email, external_id, ...) change.
  class ReindexInvoicesJob < ApplicationJob
    queue_as :meilisearch

    def perform(customer)
      customer.invoices.find_each do |invoice|
        Invoices::SearchIndexJob.perform_later(invoice.id)
      end
    end
  end
end
