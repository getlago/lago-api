# frozen_string_literal: true

module Customers
  class DestroyService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless customer.deletable?

      customer.destroy!

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end
