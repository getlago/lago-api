# frozen_string_literal: true

module V1
  class SubscriptionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.plan.code,
        status: model.status,
        billing_time: model.billing_time,
        subscription_date: model.subscription_date&.iso8601,
        started_at: model.started_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        previous_plan_code: model.previous_subscription&.plan&.code,
        next_plan_code: model.next_subscription&.plan&.code,
        previous_external_id: model.previous_subscription&.external_id,
        next_external_id: model.next_subscription&.external_id,
      }
    end
  end
end
