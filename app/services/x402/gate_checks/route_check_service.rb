# frozen_string_literal: true

module X402
  module GateChecks
    class RouteCheckService < BaseService
      CURRENCY = "USD"

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
        return refuse("plan_currency_not_supported") unless plan.amount_currency == CURRENCY
        return refuse("plan_not_usage_only") unless usage_only?
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

      def usage_only?
        plan.amount_cents.zero? &&
          plan.minimum_commitment.nil? &&
          !plan.fixed_charges.exists? &&
          !plan.charges.where(min_amount_cents: 1..).exists?
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
