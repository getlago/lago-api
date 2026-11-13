# frozen_string_literal: true

module BillingOperations
  class ScheduleService < BaseService
    Result = BaseResult

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      result
    end

    private

    attr_reader :customer
  end
end
