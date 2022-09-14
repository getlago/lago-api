# frozen_string_literal: true

module Subscriptions
  class OverrideService < BaseService
    def call(plan_args:, subscription_args:)
      ActiveRecord::Base.transaction do
        plan_result = ::Plans::CreateService.new.create(**plan_args)

        return plan_result unless plan_result.success?

        subscription_result = ::Subscriptions::CreateService.new.create(
          **subscription_args.merge(plan_id: plan_result.plan.id)
        )

        return subscription_result unless subscription_result.success?

        result.subscription = subscription_result.subscription
      end

      result
    end
  end
end
