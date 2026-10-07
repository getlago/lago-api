# frozen_string_literal: true

module X402
  module Subscriptions
    class ResolveService < BaseService
      Result = BaseResult[:subscription]

      def initialize(customer:, plan_code:, family:)
        @customer = customer
        @plan_code = plan_code
        @family = family

        super
      end

      def call
        result.subscription = customer.subscriptions.active.find_by(external_id:)
        return result if result.subscription
        return result.not_found_failure!(resource: "plan") unless plan

        result.subscription = ActiveRecord::Base.transaction(requires_new: true) do
          subscription = ::Subscriptions::CreateService.call!(
            customer:,
            plan:,
            params: {external_id:, external_customer_id: customer.external_id, billing_time: :calendar}
          ).subscription

          if subscription.active?
            subscription
          else
            result.single_validation_failure!(error_code: "subscription_not_active").raise_if_error!
          end
        end
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :customer, :plan_code, :family

      def external_id
        @external_id ||= X402::ExternalIds.subscription(customer.x402_agent_address, plan_code, family:)
      end

      def plan
        @plan ||= customer.organization.plans.parents.find_by(code: plan_code)
      end
    end
  end
end
