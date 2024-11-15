# frozen_string_literal: true

module Plans
  class UpdateAmountService < BaseService
    def initialize(plan:, amount_cents:, expected_amount_cents:)
      @plan = plan
      @amount_cents = amount_cents
      @expected_amount_cents = expected_amount_cents

      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      result.plan = plan
      return result if plan.amount_cents != expected_amount_cents

      plan.amount_cents = amount_cents

      ActiveRecord::Base.transaction do
        plan.save!
        process_pending_subscriptions
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :plan, :amount_cents, :expected_amount_cents

    def process_pending_subscriptions
      Subscription.where(plan:, status: :pending).find_each do |subscription|
        next unless subscription.previous_subscription

        if plan.yearly_amount_cents >= subscription.previous_subscription.plan.yearly_amount_cents
          Subscriptions::PlanUpgradeService.call(
            current_subscription: subscription.previous_subscription,
            plan: plan,
            params: {name: subscription.name}
          ).raise_if_error!
        end
      end
    end
  end
end
