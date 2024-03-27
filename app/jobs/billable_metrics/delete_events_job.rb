# frozen_string_literal: true

module BillableMetrics
  class DeleteEventsJob < ApplicationJob
    queue_as :default

    def perform(metric)
      return unless metric.discarded?

      deleted_at = Time.current

      Event.where(
        code: metric.code,
        subscription_id: Charge.with_discarded
          .where(billable_metric_id: metric.id)
          .joins(plan: :subscriptions).pluck("subscriptions.id")
      ).update_all(deleted_at:) # rubocop:disable Rails/SkipsModelValidations

      metric.quantified_events.update_all(deleted_at:) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
