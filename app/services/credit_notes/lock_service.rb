# frozen_string_literal: true

module CreditNotes
  class LockService < BaseService
    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      customer.with_advisory_lock("CREDIT_NOTES-#{customer.id}", timeout_seconds: 5) do
        yield
      end
    end

    def locked?
      customer.advisory_lock_exists?("CREDIT_NOTES-#{customer.id}")
    end

    private

    attr_reader :customer
  end
end
