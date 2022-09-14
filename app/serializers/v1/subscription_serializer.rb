# frozen_string_literal: true

module V1
  class SubscriptionSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        status: model.status,
        billing_time: model.billing_time,
        subscription_date: model.subscription_date&.iso8601,
        started_at: model.started_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
      }

      payload[:plan_code] = model.plan.overridden_plan_id.present? ? model.plan.overridden_plan.code : model.plan.code

      payload
    end
  end
end
