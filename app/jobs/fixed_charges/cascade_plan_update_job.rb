# frozen_string_literal: true

module FixedCharges
  class CascadePlanUpdateJob < ApplicationJob
    queue_as :default

    def perform(plan:, cascade_fixed_charges_payload:, timestamp:)
      plan.children.joins(:subscriptions).where(subscriptions: {status: %w[active pending]}).distinct.find_each do |child_plan|
        FixedCharges::CascadeChildPlanUpdateJob.perform_later(
          plan: child_plan,
          cascade_fixed_charges_payload:,
          timestamp:
        )
      end
    end
  end
end
