# frozen_string_literal: true

module Orders
  module SubscriptionCreation
    class ExecuteService < Orders::BaseExecuteService
      CALENDAR_DATE = /\A\d{4}-\d{2}-\d{2}\z/

      private

      # Subscriptions come first: they settle the customer currency the coupons and wallets
      # then reuse. No invoice_id: a subscription is invoiced later by BillSubscriptionJob, and only
      # when the plan is paid in advance.
      def create_records
        with_coupon_lock do
          subscriptions = create_subscriptions
          applied_coupons = apply_coupons
          wallets = create_wallets

          {
            subscription_ids: subscriptions.map(&:id),
            applied_coupon_ids: applied_coupons.map(&:id),
            wallet_ids: wallets.map(&:id)
          }
        end
      end

      # AppliedCoupons::CreateService takes this lock and then writes the customer row, while
      # Subscriptions::CreateService locks the row first. Taking it up front keeps one ordering for
      # the whole deal; the lock is transaction scoped, so the inner acquisition is then a no-op.
      def with_coupon_lock(&block)
        return yield if coupon_items.empty?

        ::Customers::LockService.call(customer: order.customer, scope: :coupon, &block).value
      end

      # NOTE: an external id matching a live subscription of this customer makes
      # Subscriptions::CreateService reuse, upgrade or downgrade it instead of creating one.
      def create_subscriptions
        plan_items.map do |item|
          plan = find_plan!(item["id"])

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
          # Both quoted ids are stable, so a retry after a failed execution reuses the same external
          # id. NOTE: localId is optional on plan items, so an item carrying neither mints a new
          # external id on every attempt.
          external_id: payload["subscriptionExternalId"].presence || item["localId"].presence || SecureRandom.uuid,
          # Mandatory under the api source, where the customer is normally identified by it rather
          # than passed. Inert otherwise, but the customer here is always the order's own.
          external_customer_id: order.customer.external_id,
          name: payload["subscriptionName"],
          billing_time: payload["billingTime"],
          subscription_at: subscription_datetime(payload["startDate"]),
          ending_at: subscription_datetime(payload["endDate"]),
          payment_method: payment_method_params(payload),
          billing_entity_id: quoted_billing_entity_id,
          plan_overrides: plan_overrides(item, plan).presence,
          usage_thresholds: usage_thresholds(item).presence
        }.compact
      end

      # The raw column, not the applicable one: a deal that named no entity leaves the subscription
      # and the wallets inheriting the customer's at billing time, which is what NULL means here.
      def quoted_billing_entity_id
        order.quote_version.billing_entity_id
      end

      # The payload may carry a bare date. A date reaches a datetime attribute as midnight UTC,
      # which is the previous day for a customer west of UTC: Subscriptions::CreateService would
      # then take its past subscription path and anniversary date. A calendar date means that day
      # for the customer, so it is read in their timezone.
      def subscription_datetime(payload_value)
        value = payload_value.presence
        date = calendar_date(value)
        return value if date.nil?

        date.in_time_zone(order.customer.applicable_timezone)
      end

      # A string that only looks like a date is left alone for Subscriptions::ValidateService to
      # reject.
      def calendar_date(value)
        return nil unless value.is_a?(String) && CALENDAR_DATE.match?(value)

        Utils::Datetime.parse_iso8601_date(value)
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
          amount_currency: overrides["amountCurrency"],
          invoice_display_name: overrides["invoiceDisplayName"],
          name: overrides["name"],
          description: overrides["description"],
          trial_period: overrides["trialPeriod"],
          minimum_commitment: minimum_commitment(overrides, plan),
          charges: charge_overrides(item, plan).presence,
          fixed_charges: fixed_charge_overrides(item, plan).presence
        }.compact
      end

      # Plans::OverrideService builds a fresh Commitment rather than duplicating the plan's own, and
      # Commitment rejects a nil amount, so an override renaming the commitment without repricing it
      # only reaches a valid record if the plan's own amount is forwarded here.
      def minimum_commitment(overrides, plan)
        commitment = overrides["minimumCommitment"]
        return nil if commitment.blank?

        {
          amount_cents: commitment["amountCents"] || plan.minimum_commitment&.amount_cents,
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
        charge = plan.charges.find { |plan_charge| plan_charge.id == charge_id }

        result.not_found_failure!(resource: "charge").raise_if_error! if charge.nil?

        if charge_model_changed?(snapshot, charge)
          result.single_validation_failure!(field: :charge_model, error_code: "charge_model_changed").raise_if_error!
        end

        charge_id
      end

      def fixed_charge_id!(item, plan, add_on_code)
        snapshot = Array(item.dig("payload", "fixedCharges")).find do |fixed_charge|
          fixed_charge.dig("addOn", "code") == add_on_code
        end
        fixed_charge_id = snapshot&.dig("id")
        fixed_charge = plan.fixed_charges.find { |plan_fixed_charge| plan_fixed_charge.id == fixed_charge_id }

        result.not_found_failure!(resource: "fixed_charge").raise_if_error! if fixed_charge.nil?

        if charge_model_changed?(snapshot, fixed_charge)
          result
            .single_validation_failure!(field: :fixed_charge_model, error_code: "fixed_charge_model_changed")
            .raise_if_error!
        end

        fixed_charge_id
      end

      # The negotiated properties were approved against the model the snapshot pinned. A catalog
      # model change since then makes them invalid for the charge they now land on, and the override
      # services fail on that inside Plans::OverrideService, which ignores their result: the charge
      # would be dropped and the subscription would bill nothing for it.
      def charge_model_changed?(snapshot, chargeable)
        charge_model = snapshot["chargeModel"]
        return false if charge_model.nil?

        charge_model != chargeable.charge_model
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

      # Only the override states a currency: the payload's own is the catalog snapshot, and
      # AppliedCoupons::CreateService already falls back to the live coupon's when none is given.
      def coupon_params(item)
        {
          amount_cents: effective_value(item, "amountCents"),
          amount_currency: item.dig("overrides", "amountCurrency"),
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
          billing_entity_id: quoted_billing_entity_id,
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
          # Wallets::CreateService reads the codes under the api source and the ids otherwise, so
          # the limitation must be stated both ways for the execution to be transport independent.
          billable_metric_codes: applies_to["billableMetricCodes"].presence,
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

      def plan_items
        Array(billing_items["plans"])
      end

      def coupon_items
        Array(billing_items["coupons"])
      end

      def wallet_credit_items
        Array(billing_items["walletCredits"])
      end

      # Subscriptions::CreateService assigns the negotiated amount onto the plan it is given and
      # Plans::OverrideService dups it, so two items on the same plan get their own instance
      # instead of inheriting each other's amount.
      def find_plan!(plan_id)
        plan = order.organization.plans.includes(:charges, :fixed_charges, :minimum_commitment).find_by(id: plan_id)
        result.not_found_failure!(resource: "plan").raise_if_error! if plan.nil?

        plan
      end

      def coupons_by_id
        @coupons_by_id ||= order
          .organization
          .coupons
          .where(id: coupon_items.map { |item| item["id"] })
          .index_by(&:id)
      end
    end
  end
end
