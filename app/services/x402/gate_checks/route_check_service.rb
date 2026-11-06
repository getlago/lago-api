# frozen_string_literal: true

module X402
  module GateChecks
    class RouteCheckService < BaseService
      Result = BaseResult[:plan]

      def initialize(organization:, plan_code:, billable_metric_code:)
        @organization = organization
        @plan_code = plan_code
        @billable_metric_code = billable_metric_code

        super
      end

      def call
        return result.not_found_failure!(resource: "plan") unless plan
        return result.not_found_failure!(resource: "charge") if charges.empty?
        return refuse(plan_refusal) if plan_refusal
        return refuse("charge_not_targeted") unless targeted?
        return refuse("charge_not_invoiceable") if charges.any? { |charge| charge.pay_in_advance? && !charge.invoiceable? }

        result.plan = plan
        result
      end

      private

      attr_reader :organization, :plan_code, :billable_metric_code

      def plan
        @plan ||= organization.plans.parents.find_by(code: plan_code)
      end

      def charges
        @charges ||= plan.charges.joins(:billable_metric).where(billable_metric: {code: billable_metric_code}).to_a
      end

      def plan_refusal
        @plan_refusal ||= X402::PlanEligibility.refusal(plan)
      end

      def targeted?
        organization.events_targeting_wallets_enabled? && charges.all?(&:accepts_target_wallet)
      end

      def refuse(code)
        result.single_validation_failure!(error_code: code)
      end
    end
  end
end
