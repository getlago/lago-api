# frozen_string_literal: true

module V1
  # Serializes the diff produced by Plans::UpdateService for the `plan.updated_details` webhook.
  #
  # `changes` is a map of changed field => {from:, to:} covering the plan's own
  # attributes plus the cheap single-model associations (minimum_commitment, metadata).
  #
  # `associations_changed` is a map of association => boolean flagging which of the
  # nested associations were modified by the update (consumers can refetch the plan
  # or listen to `plan.updated` for the full detail).
  class PlanUpdatedDetailsSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        changed_at: model.updated_at.iso8601,
        changes: options[:changes] || {},
        associations_changed: options[:associations_changed] || {}
      }
    end
  end
end
