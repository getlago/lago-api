# frozen_string_literal: true

module Orders
  module SubscriptionAmendment
    # An amendment restates one plan on a live subscription, so the payload it carries is a
    # subscription_creation one and the whole mapping is inherited. Only the transition differs: the
    # quoted plan replaces the one the target runs on, instead of a subscription being created.
    class ExecuteService < Orders::SubscriptionCreation::ExecuteService
      private

      def create_records
        validate_target_subscription!

        super.merge(terminated_subscription_ids:)
      end

      def create_subscriptions
        [amend_subscription]
      end

      # The plan change carries the target's own binding over, so the wallets created alongside follow
      # the entity that will bill them rather than the customer's default.
      def quoted_billing_entity_id
        target_subscription&.billing_entity_id
      end

      # Subscriptions::CreateService is the entry point the API and the UI already use for a plan
      # change, so the amendment inherits Lago's own semantics in both directions: a raise rotates
      # the subscription now, keeping the external id and the billing anchor, while a reduction keeps
      # the target running and schedules the replacement for the next billing day.
      def amend_subscription
        subscription = ::Subscriptions::CreateService.call!(
          customer: order.customer,
          plan: quoted_plan,
          params: amendment_params
        ).subscription

        # CreateService loaded its own instance of the target, so ours is stale.
        target_subscription.reload
        subscription = target_subscription.next_subscription if subscription.id == target_subscription.id

        update_usage_thresholds!(subscription)

        subscription
      end

      def amendment_params
        payload = plan_item["payload"] || {}

        {
          # Resolves the target through editable_subscriptions, so the plan change always dispatches
          # on it instead of creating a second subscription.
          subscription_id: target_subscription.id,
          external_id: target_subscription.external_id,
          # Mandatory under the api source, see Orders::SubscriptionCreation::ExecuteService.
          external_customer_id: order.customer.external_id,
          # CreateService strips this to a string, so the target's own name only survives when it is
          # passed back.
          name: payload["subscriptionName"].presence || target_subscription.name,
          # The amendment restates the contract term. A quote carrying no ending date leaves the
          # target's own in place.
          ending_at: subscription_datetime(payload["endDate"]),
          payment_method: payment_method_params(payload)
        }.compact
      end

      # The negotiated plan is built here rather than passed as plan_overrides because the plan
      # change dispatches on plan ids before prices: a repricing of the same catalog plan would match
      # on id and return the target untouched. An override plan always carries a fresh id, so the
      # comparison reaches the negotiated amount whatever the quote restates.
      def quoted_plan
        @quoted_plan ||= ::Plans::OverrideService.call!(
          plan: catalog_plan,
          params: plan_overrides(plan_item, catalog_plan).with_indifferent_access
        ).plan
      end

      def catalog_plan
        @catalog_plan ||= find_plan!(plan_item["id"])
      end

      # Thresholds ride on the subscription, and CreateService would apply them to whatever the plan
      # change returns, which for a reduction is the target rather than the replacement it scheduled.
      def update_usage_thresholds!(subscription)
        thresholds = usage_thresholds(plan_item)
        return if thresholds.empty?

        ::Subscriptions::UpdateUsageThresholdsService.call!(
          subscription:,
          usage_thresholds_params: thresholds,
          partial: false
        )
      end

      # Empty for a scheduled amendment: the target keeps running until the end of the period.
      def terminated_subscription_ids
        target_subscription.reload.terminated? ? [target_subscription.id] : []
      end

      # Re-runs the approval gate: weeks pass between approval and execution and every state it
      # covers can change in between. A failure here rolls the whole amendment back, leaving the
      # order failed with the reason recorded and the signed order form untouched.
      def validate_target_subscription!
        if plan_items.count != 1
          result.single_validation_failure!(field: :plans, error_code: "single_plan_expected").raise_if_error!
        end

        if target_subscription.nil? || target_subscription.customer_id != order.customer_id
          result.not_found_failure!(resource: "subscription").raise_if_error!
        end

        return if target_subscription.active?

        result
          .single_validation_failure!(field: :subscription, error_code: "subscription_not_active")
          .raise_if_error!
      end

      def target_subscription
        return @target_subscription if defined?(@target_subscription)

        @target_subscription = order.quote.subscription
      end

      def plan_item
        @plan_item ||= plan_items.first
      end
    end
  end
end
