# frozen_string_literal: true

module AppliedCoupons
  class LockService < BaseService
    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      customer.with_advisory_lock("COUPONS-#{customer.id}", timeout_seconds: 5) do
        yield
      end
    end

    def locked?
      customer.advisory_lock_exists?("COUPONS-#{customer.id}")
    end

    private

    attr_reader :customer
  end
end
