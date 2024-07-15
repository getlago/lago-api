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
        plan_code: model.plan.code,
        status: model.status,
        billing_time: model.billing_time,
        subscription_at: model.subscription_at&.iso8601,
        started_at: model.started_at&.iso8601,
        trial_ended_at: model.trial_ended_at&.iso8601,
        ending_at: model.ending_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        previous_plan_code: model.previous_subscription&.plan&.code,
        next_plan_code: model.next_subscription&.plan&.code,
        downgrade_plan_date: model.downgrade_plan_date&.iso8601
      }

      payload = payload.merge(customer:) if include?(:customer)
      payload = payload.merge(plan:) if include?(:plan)

      payload
    end

    private

    def customer
      ::V1::CustomerSerializer.new(model.customer).serialize
    end

    def plan
      ::V1::PlanSerializer.new(
        model.plan,
        includes: %i[charges taxes minimum_commitment]
      ).serialize
    end
  end
end
