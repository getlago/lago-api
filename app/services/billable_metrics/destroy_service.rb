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

      track_billable_metric_deleted

      result.billable_metric = metric
      result
    end

    private

    attr_reader :metric

    def track_billable_metric_deleted
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'billable_metric_deleted',
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregation_type: metric.aggregation_type,
          aggregation_property: metric.field_name,
          organization_id: metric.organization_id,
        },
      )
    end
  end
end
