# frozen_string_literal: true

module Agents
  module Billing
    class EnrollService < BaseService
      Result = BaseResult[:subscription, :wallet]

      def initialize(storefront:, registration:, plan_code:)
        @storefront = storefront
        @registration = registration
        @plan_code = plan_code

        super
      end

      def call
        return result.single_validation_failure!(field: :plan_code, error_code: "plan_not_sold") unless sold_plan && plan
        return result.single_validation_failure!(field: :plan_code, error_code: "plan_not_usage_only") unless X402::PlanEligibility.usage_only?(plan)

        ActiveRecord::Base.transaction do
          registration.lock!

          customer = registration.customer || create_customer
          result.subscription = registration.subscription || create_subscription(customer)
          if (result.subscription.plan.parent_id || result.subscription.plan_id) != plan.id
            result.not_allowed_failure!(code: "already_enrolled").raise_if_error!
          end

          result.wallet = registration.wallet || create_wallet(customer)
        end

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :storefront, :registration, :plan_code

      def sold_plan
        @sold_plan ||= storefront.sold_plan(plan_code)
      end

      def plan
        @plan ||= storefront.plans_for_sale.find_by(code: plan_code)
      end

      def create_customer
        ::Customers::CreateService.call!(
          organization_id: storefront.organization_id,
          external_id: Agents::ExternalIds.customer(registration),
          name: "Agent · #{registration.id}",
          finalize_zero_amount_invoice: :skip,
          exclude_from_dunning_campaign: true
        ).customer
      end

      def create_subscription(customer)
        subscription = ::Subscriptions::CreateService.call!(
          customer:,
          plan:,
          params: {external_id: Agents::ExternalIds.subscription(registration), external_customer_id: customer.external_id, billing_time: :calendar}
        ).subscription

        if subscription.active?
          subscription
        else
          result.single_validation_failure!(error_code: "subscription_not_active").raise_if_error!
        end
      end

      def create_wallet(customer)
        ::Wallets::CreateService.call!(
          params: {
            organization_id: storefront.organization_id,
            customer:,
            code: Agents::Registration::WALLET_CODE,
            name: storefront.name,
            currency: plan.amount_currency,
            rate_amount: 1,
            paid_top_up_min_amount_cents: sold_plan["minimum_topup_cents"],
            paid_top_up_max_amount_cents: sold_plan["maximum_topup_cents"]
          }
        ).wallet
      end
    end
  end
end
