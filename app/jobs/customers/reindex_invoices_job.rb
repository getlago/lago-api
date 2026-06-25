# frozen_string_literal: true

module Customers
  class ReindexInvoicesJob < ApplicationJob
    queue_as :meilisearch

    def perform(customer)
      customer.invoices.find_each do |invoice|
        Invoices::SearchIndexJob.perform_later(invoice.id)
      end
    end
  end
end
