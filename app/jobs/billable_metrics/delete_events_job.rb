# frozen_string_literal: true

module BillableMetrics
  class DeleteEventsJob < ApplicationJob
    queue_as :default

    def perform(metric)
      return unless metric.discarded?

      deleted_at = Time.current

      Event.joins(subscription: [:plan])
        .where(code: metric.code, plan: { id: metric.plans.pluck(:id) })
        .update_all(deleted_at:) # rubocop:disable Rails/SkipsModelValidations

      metric.persisted_events.update_all(deleted_at:) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
