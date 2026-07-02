# frozen_string_literal: true

module Customers
  class ReindexInvoicesJob < ApplicationJob
    queue_as :meilisearch

    def perform(customer_id)
      customer = Customer.with_discarded.find_by(id: customer_id)
      return if customer.nil?

      customer.invoices.find_each do |invoice|
        Invoices::SearchIndexJob.perform_later(invoice.id)
      end
    end
  end
end
