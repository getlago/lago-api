# frozen_string_literal: true

module V1
  class SubscriptionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        customer_id: model.customer.customer_id,
        name: model.name,
        plan_code: model.plan.code,
        status: model.status,
        started_at: model.started_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
