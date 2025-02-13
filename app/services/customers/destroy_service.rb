# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      customer.discard!

      Customers::TerminateRelationsJob.perform_later(customer_id: customer.id)

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end
