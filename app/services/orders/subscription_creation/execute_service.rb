# frozen_string_literal: true

module Orders
  module SubscriptionCreation
    # Internal: premium/feature-flag gates live in Orders::ExecuteService, always call through it.
    class ExecuteService < BaseService
      Result = BaseResult[:order]

      def initialize(order:)
        @order = order

        super
      end

      def call
        return success_result if order.executed?

        if order.execution_mode.blank?
          return result.single_validation_failure!(field: :execution_mode, error_code: "value_is_mandatory")
        end

        Order.transaction do
          Quotes::LockService.call(quote: order.quote) do
            order.reload
            next success_result if order.executed?

            mark_executed!(execute_in_lago? ? create_deal : {})

            result.order = order
          end
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        record_execution_failure!(result.record_validation_failure!(record: e.record))
      rescue BaseService::FailedResult => e
        record_execution_failure!(e.result)
      end

      private

      attr_reader :order

      def success_result
        result.order = order
        result
      end

      def execute_in_lago?
        order.execution_mode == Order::EXECUTION_MODES[:execute_in_lago]
      end

      # Subscriptions come first: they settle the customer currency the coupons and wallets
      # then reuse.
      def create_deal
        subscriptions = create_subscriptions
        applied_coupons = apply_coupons
        wallets = create_wallets

        {
          subscription_ids: subscriptions.map(&:id),
          applied_coupon_ids: applied_coupons.map(&:id),
          wallet_ids: wallets.map(&:id)
        }
      end

      # invoice_id stays nil: a subscription is invoiced later by BillSubscriptionJob, and only
      # when the plan is paid in advance.
      def mark_executed!(created)
        executed_at = Time.current

        order.update!(
          status: :executed,
          executed_at:,
          execution_record: {
            executed_at: executed_at.iso8601,
            execution_mode: order.execution_mode,
            invoice_id: nil,
            subscription_ids: [],
            applied_coupon_ids: [],
            wallet_ids: [],
            errors: []
          }.merge(created)
        )
      end

      # The transaction has already rolled back, so this trace is the only durable outcome
      # of the attempt. Recording it moves the order to failed, excluding it from the
      # executable scope; retrying is a deliberate manual action.
      def record_execution_failure!(failed_result)
        order.update!(
          status: :failed,
          executed_at: nil,
          execution_record: {
            executed_at: nil,
            execution_mode: order.execution_mode,
            invoice_id: nil,
            subscription_ids: [],
            applied_coupon_ids: [],
            wallet_ids: [],
            errors: execution_errors(failed_result.error)
          }
        )

        failed_result
      end

      def execution_errors(error)
        if error.respond_to?(:messages)
          error.messages.values.flatten
        elsif error.respond_to?(:code)
          [error.code]
        else
          [error.message]
        end
      end

      # NOTE: an external id matching a live subscription of this customer makes
      # Subscriptions::CreateService reuse, upgrade or downgrade it instead of creating one.
      def create_subscriptions
        plan_items.map do |item|
          plan = plans_by_id[item["id"]]
          result.not_found_failure!(resource: "plan").raise_if_error! if plan.nil?

          ::Subscriptions::CreateService.call!(
            customer: order.customer,
            plan:,
            params: subscription_params(item, plan)
          ).subscription
        end
      end

      def subscription_params(item, plan)
        payload = item["payload"] || {}

        {
          external_id: payload["subscriptionExternalId"].presence || SecureRandom.uuid,
          name: payload["subscriptionName"],
          billing_time: payload["billingTime"],
          subscription_at: payload["startDate"] || quote_version.start_date,
          ending_at: payload["endDate"] || quote_version.end_date,
          payment_method: payment_method_params(payload),
          plan_overrides: plan_overrides(item, plan).presence,
          usage_thresholds: usage_thresholds(item).presence
        }.compact
      end

      # PaymentMethods::ValidateService refuses an id without its type.
      def payment_method_params(payload)
        payment_method_id = payload["paymentMethodId"]
        return nil if payment_method_id.nil?

        {payment_method_type: "provider", payment_method_id:}
      end

      def plan_overrides(item, plan)
        overrides = item["overrides"] || {}

        {
          amount_cents: overrides["amountCents"],
          invoice_display_name: overrides["invoiceDisplayName"],
          name: overrides["name"],
          description: overrides["description"],
          trial_period: overrides["trialPeriod"],
          minimum_commitment: minimum_commitment(overrides),
          charges: charge_overrides(item, plan).presence,
          fixed_charges: fixed_charge_overrides(item, plan).presence
        }.compact
      end

      def minimum_commitment(overrides)
        commitment = overrides["minimumCommitment"]
        return nil if commitment.blank?

        {
          amount_cents: commitment["amountCents"],
          invoice_display_name: commitment["invoiceDisplayName"]
        }.compact.presence
      end

      # chargeModel is not forwarded: Charges::OverrideService cannot switch models and ignores it.
      def charge_overrides(item, plan)
        Array(item.dig("overrides", "charges")).map do |override|
          {
            id: charge_id!(item, plan, override["billableMetricCode"]),
            properties: override["properties"],
            min_amount_cents: override["minAmountCents"],
            invoice_display_name: override["invoiceDisplayName"]
          }.compact
        end
      end

      def fixed_charge_overrides(item, plan)
        Array(item.dig("overrides", "fixedCharges")).map do |override|
          {
            id: fixed_charge_id!(item, plan, override["addOnCode"]),
            units: override["units"],
            properties: override["properties"],
            invoice_display_name: override["invoiceDisplayName"]
          }.compact
        end
      end

      # Plans::OverrideService matches by id and silently ignores one it cannot find, which would
      # bill the catalog price. The charge must still be on the plan, whatever happened to the
      # catalog since the quote was approved.
      def charge_id!(item, plan, metric_code)
        snapshot = Array(item.dig("payload", "charges")).find do |charge|
          charge.dig("billableMetric", "code") == metric_code
        end
        charge_id = snapshot&.dig("id")

        unless plan.charges.any? { |charge| charge.id == charge_id }
          result.not_found_failure!(resource: "charge").raise_if_error!
        end

        charge_id
      end

      def fixed_charge_id!(item, plan, add_on_code)
        snapshot = Array(item.dig("payload", "fixedCharges")).find do |fixed_charge|
          fixed_charge.dig("addOn", "code") == add_on_code
        end
        fixed_charge_id = snapshot&.dig("id")

        unless plan.fixed_charges.any? { |fixed_charge| fixed_charge.id == fixed_charge_id }
          result.not_found_failure!(resource: "fixed_charge").raise_if_error!
        end

        fixed_charge_id
      end

      # Thresholds ride on the subscription, not on the overridden plan: plan_overrides
      # .usage_thresholds is the deprecated path and combining both is refused upstream.
      def usage_thresholds(item)
        Array(item.dig("overrides", "usageThresholds")).map do |threshold|
          {
            amount_cents: threshold["amountCents"],
            recurring: threshold["recurring"],
            threshold_display_name: threshold["thresholdDisplayName"]
          }.compact
        end
      end

      def apply_coupons
        coupon_items.map do |item|
          coupon = coupons_by_id[item["id"]]
          result.not_found_failure!(resource: "coupon").raise_if_error! if coupon.nil?

          ::AppliedCoupons::CreateService.call!(
            customer: order.customer,
            coupon:,
            params: coupon_params(item)
          ).applied_coupon
        end
      end

      # amount_currency is left out on purpose so it falls back to the coupon's own currency,
      # which approve validation pins to the deal currency.
      def coupon_params(item)
        {
          amount_cents: effective_value(item, "amountCents"),
          percentage_rate: effective_value(item, "percentageRate"),
          frequency: effective_value(item, "frequency"),
          frequency_duration: effective_value(item, "frequencyDuration")
        }.compact
      end

      def create_wallets
        wallet_credit_items.map do |item|
          ::Wallets::CreateService.call!(params: wallet_params(item)).wallet
        end
      end

      def wallet_params(item)
        payload = item["payload"] || {}

        {
          organization_id: order.organization_id,
          customer: order.customer,
          currency: payload["currency"] || order.currency,
          name: payload["name"],
          rate_amount: payload["rateAmount"],
          paid_credits: payload["paidCredits"],
          granted_credits: payload["grantedCredits"],
          expiration_at: payload["expirationAt"],
          purchase_order_number: payload["purchaseOrderNumber"],
          invoice_requires_successful_payment: payload["invoiceRequiresSuccessfulPayment"],
          applies_to: applies_to(payload),
          recurring_transaction_rules: recurring_transaction_rules(payload)
        }.compact
      end

      def applies_to(payload)
        applies_to = payload["appliesTo"]
        return nil if applies_to.blank?

        {
          fee_types: applies_to["feeTypes"].presence,
          billable_metric_ids: billable_metric_ids!(applies_to["billableMetricCodes"])
        }.compact.presence
      end

      # Outside api context Wallets::CreateService resolves the limitation by id, so a code that
      # no longer exists would create a wallet without its limitation.
      def billable_metric_ids!(codes)
        return nil if codes.blank?

        ids = order.organization.billable_metrics.where(code: codes).pluck(:id)
        result.not_found_failure!(resource: "billable_metric").raise_if_error! if ids.count != codes.uniq.count

        ids
      end

      def recurring_transaction_rules(payload)
        rules = Array(payload["recurringTransactionRules"]).map do |rule|
          {
            trigger: rule["trigger"],
            interval: rule["interval"],
            method: rule["method"],
            threshold_credits: rule["thresholdCredits"],
            target_ongoing_balance: rule["targetOngoingBalance"],
            grants_target_top_up: rule["grantsTargetTopUp"],
            paid_credits: rule["paidCredits"],
            granted_credits: rule["grantedCredits"],
            started_at: rule["startedAt"],
            expiration_at: rule["expirationAt"],
            transaction_name: rule["transactionName"],
            invoice_requires_successful_payment: rule["invoiceRequiresSuccessfulPayment"]
          }.compact
        end

        rules.presence
      end

      def effective_value(item, field)
        item.dig("overrides", field) || item.dig("payload", field)
      end

      def plan_items
        Array(billing_items["plans"])
      end

      def coupon_items
        Array(billing_items["coupons"])
      end

      def wallet_credit_items
        Array(billing_items["walletCredits"])
      end

      def plans_by_id
        @plans_by_id ||= order
          .organization
          .plans
          .includes(:charges, :fixed_charges)
          .where(id: plan_items.map { |item| item["id"] })
          .index_by(&:id)
      end

      def coupons_by_id
        @coupons_by_id ||= order
          .organization
          .coupons
          .where(id: coupon_items.map { |item| item["id"] })
          .index_by(&:id)
      end

      def billing_items
        @billing_items ||= quote_version.billing_items || {}
      end

      def quote_version
        order.quote_version
      end
    end
  end
end
