# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
    def initialize(customer:)
      @customer = customer

      super
    end

    activity_loggable(
      action: "customer.deleted",
      record: -> { customer }
    )

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      customer.discard!

      Customers::TerminateRelationsJob.perform_later(customer_id: customer.id)
      # Drop the discarded customer's denormalized fields from the invoice index,
      # matching the Postgres search which excluded discarded customers.
      Customers::ReindexInvoicesJob.perform_after_commit(customer) if MeilisearchClient.enabled?

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end
