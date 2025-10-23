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
        started_at: model.started_at&.iso8601(3),
        trial_ended_at: model.trial_ended_at&.iso8601,
        ending_at: model.ending_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        previous_plan_code: model.previous_subscription&.plan&.code,
        next_plan_code: model.next_subscription&.plan&.code,
        downgrade_plan_date: model.downgrade_plan_date&.iso8601,
        current_billing_period_started_at: dates_service.charges_from_datetime&.iso8601,
        current_billing_period_ending_at: dates_service.charges_to_datetime&.iso8601,
        on_termination_credit_note: model.on_termination_credit_note,
        on_termination_invoice: model.on_termination_invoice
      }

      payload = payload.merge(customer:) if include?(:customer)
      payload.merge!(entitlements) if include?(:entitlements)
      payload = payload.merge(plan:) if include?(:plan)
      payload = payload.merge(usage_threshold:) if include?(:usage_threshold)

      payload
    end

    private

    def customer
      ::V1::CustomerSerializer.new(model.customer).serialize
    end

    def entitlements
      ::CollectionSerializer.new(
        ::Entitlement::SubscriptionEntitlement.for_subscription(model),
        ::V1::Entitlement::SubscriptionEntitlementSerializer,
        collection_name: "entitlements"
      ).serialize
    end

    def plan
      ::V1::PlanSerializer.new(
        model.plan,
        includes: %i[charges usage_thresholds taxes minimum_commitment]
      ).serialize
    end

    def usage_threshold
      ::V1::UsageThresholdSerializer.new(options[:usage_threshold]).serialize
    end

    def dates_service
      @dates_service ||= ::Subscriptions::DatesService.new_instance(model, Time.current, current_usage: true)
    end
  end
end
