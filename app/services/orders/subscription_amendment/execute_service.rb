# frozen_string_literal: true

module Orders
  module SubscriptionAmendment
    # An amendment restates one plan on a live subscription, so the payload it carries is a
    # subscription_creation one and the whole mapping is inherited. Only the transition differs: the
    # target is terminated and replaced, instead of a subscription being created.
    class ExecuteService < Orders::SubscriptionCreation::ExecuteService
      private

      def create_records
        validate_target_subscription!

        super.merge(terminated_subscription_ids: [target_subscription.id])
      end

      def create_subscriptions
        [amend_subscription]
      end

      # PlanUpgradeService is the existing composition of terminate then create on a single external
      # id: it keeps subscription_at and billing_time so the billing anchor does not move, sets
      # previous_subscription_id so the replacement's first fee is prorated from the amendment day,
      # cancels a pending downgrade, and leaves ActivateService to terminate the target, credit its
      # unconsumed pay-in-advance time and enqueue one combined invoice after commit.
      def amend_subscription
        subscription = ::Subscriptions::PlanUpgradeService.call!(
          current_subscription: target_subscription,
          plan: quoted_plan,
          params: amendment_params
        ).subscription

        update_usage_thresholds!(subscription)

        subscription
      end

      def amendment_params
        payload = plan_item["payload"] || {}

        {
          # PlanUpgradeService strips this to a string, so the target's own name only survives when
          # it is passed back.
          name: payload["subscriptionName"].presence || target_subscription.name,
          # The amendment restates the contract term. A quote carrying no ending date leaves the
          # target's own in place.
          ending_at: subscription_datetime(payload["endDate"], quote_version.end_date),
          payment_method: payment_method_params(payload),
          # Never .presence here, unlike the creation path: an empty override still has to mint a
          # child plan. Were the replacement to share the target's plan id, ActivateService would
          # take its standalone branch, leaving the target active and its external id duplicated.
          plan_overrides: plan_overrides(plan_item, quoted_plan)
        }.compact
      end

      # Thresholds ride on the subscription and PlanUpgradeService has no such parameter, so they
      # reach the replacement the way Subscriptions::CreateService applies them to a new one.
      def update_usage_thresholds!(subscription)
        thresholds = usage_thresholds(plan_item)
        return if thresholds.empty?

        ::Subscriptions::UpdateUsageThresholdsService.call!(
          subscription:,
          usage_thresholds_params: thresholds,
          partial: false
        )
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

        unless target_subscription.active?
          result
            .single_validation_failure!(field: :subscription, error_code: "subscription_not_active")
            .raise_if_error!
        end

        validate_amendment_direction!
      end

      # Mirrors Subscriptions::ActivateService#upgrade?, the price comparison that decides how both
      # the terminated subscription and its replacement are prorated. A cheaper replacement takes
      # the downgrade path, which bills the target for the whole current period and credits none of
      # its unconsumed pay-in-advance time. Same check as the approval gate, see
      # QuoteVersions::Validators::SubscriptionAmendment::BusinessValidator.
      def validate_amendment_direction!
        amount_cents = plan_item.dig("overrides", "amountCents") || quoted_plan.amount_cents
        quoted = Plan.new(interval: quoted_plan.interval, amount_cents:)
        return if quoted.yearly_amount_cents >= target_subscription.plan.yearly_amount_cents

        result
          .single_validation_failure!(field: :plan, error_code: "amendment_decreases_amount")
          .raise_if_error!
      end

      def target_subscription
        return @target_subscription if defined?(@target_subscription)

        @target_subscription = order.quote.subscription
      end

      def plan_item
        @plan_item ||= plan_items.first
      end

      def quoted_plan
        @quoted_plan ||= find_plan!(plan_item["id"])
      end
    end
  end
end
