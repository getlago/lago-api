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

      ActiveRecord::Base.transaction do
        metric.discard!
        metric.charges.discard_all
        metric.groups.each do |group|
          group.discard!
          group.properties.discard_all
        end
      end

      # NOTE: Discard all related events asynchronously.
      BillableMetrics::DeleteEventsJob.perform_later(metric)

      result.billable_metric = metric
      result
    end

    private

    attr_reader :metric
  end
end
