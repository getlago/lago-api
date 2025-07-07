# frozen_string_literal: true

module Charges
  class CreateChildrenJob < ApplicationJob
    queue_as "default"

    def perform(charge:, payload:)
      plan = charge.plan
      return unless plan&.children&.any?

      plan.children.order(created_at: :asc).pluck(:id).each_slice(20) do |child_ids|
        Charges::CreateChildrenBatchJob.perform_later(
          child_ids:,
          charge:,
          payload:
        )
      end
    end
  end
end
