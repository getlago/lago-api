# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(metric:)
      @metric = metric
      super
    end

    def call
      return result.not_found_failure!(resource: 'billable_metric') unless metric

      metric.destroy!
      result.billable_metric = metric
      result
    end

    private

    attr_reader :metric
  end
end
