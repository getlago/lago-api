# frozen_string_literal: true

module Contracts
  class LockAdvanceAggregationService < BaseService
    Result = BaseResult[:value]

    def initialize(metered_item:)
      @metered_item = metered_item
      super
    end

    def call(&block)
      contract = metered_item.contract
      result.value = if contract
        contract.with_advisory_lock!("advance_aggregation_#{contract.id}_#{metered_item.invoiceable.id}", &block)
      else
        yield
      end

      result
    end

    private

    attr_reader :metered_item
  end
end
