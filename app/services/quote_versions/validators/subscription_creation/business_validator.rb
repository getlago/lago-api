# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      class BusinessValidator < ::BaseValidator
        include Currencies
        include CurrencyValidation

        def initialize(result, quote_version:, billing_items:, scope:)
          @quote_version = quote_version
          @billing_items = billing_items
          @scope = scope

          super
        end

        def valid?
          validate_currency
          validate_dates
          validate_plans
          validate_coupons
          validate_wallet_credits

          if errors?
            result.validation_failure!(errors:)
            return false
          end

          true
        end

        private

        attr_reader :quote_version, :billing_items, :scope

        # NOTE: payment terms are not validated yet, the quote-level field lands with LAGO-1529
        def validate_dates
          start_date = quote_version.start_date
          end_date = quote_version.end_date

          if scope == :approve
            add_error(field: :start_date, error_code: "value_is_mandatory") if start_date.blank?
            add_error(field: :end_date, error_code: "value_is_mandatory") if end_date.blank?
          end

          if start_date.present? && end_date.present? && end_date < start_date
            add_error(field: :start_date, error_code: "invalid_date_range")
          end
        end

        def validate_plans
          plans.each_with_index do |plan_item, index|
            plan = known_plans_by_id[plan_item["id"]]

            if plan.nil?
              add_error(field: plan_field(index, "id"), error_code: "plan_not_found")
              next
            end

            validate_plan_currency(plan, index)
            validate_charge_overrides(plan_item, index)
            validate_fixed_charge_overrides(plan_item, index)
          end
        end

        # NOTE: overrides carry no plan-level currency, so the plan's own currency is the one
        # billed: a EUR deal on a USD plan would invoice the customer in USD.
        def validate_plan_currency(plan, index)
          return if self.class.currency_list.exclude?(quote_version.currency)

          if plan.amount_currency != quote_version.currency
            add_error(field: plan_field(index, "id"), error_code: "currencies_does_not_match")
          end
        end

        def validate_charge_overrides(plan_item, index)
          charge_overrides = (plan_item["overrides"] || {})["charges"] || []

          charge_overrides.each_with_index do |charge_override, charge_index|
            unless known_charge_metric_codes.include?([plan_item["id"], charge_override["billableMetricCode"]])
              add_error(
                field: plan_field(index, "overrides.charges.#{charge_index}.billableMetricCode"),
                error_code: "charge_not_found"
              )
            end
          end
        end

        def validate_fixed_charge_overrides(plan_item, index)
          fixed_charge_overrides = (plan_item["overrides"] || {})["fixedCharges"] || []

          fixed_charge_overrides.each_with_index do |fixed_charge_override, fixed_charge_index|
            validate_fixed_charge_units(fixed_charge_override, index, fixed_charge_index)

            unless known_fixed_charge_add_on_codes.include?([plan_item["id"], fixed_charge_override["addOnCode"]])
              add_error(
                field: plan_field(index, "overrides.fixedCharges.#{fixed_charge_index}.addOnCode"),
                error_code: "fixed_charge_not_found"
              )
            end
          end
        end

        # units is forwarded verbatim to FixedCharges::OverrideService, and FixedCharge validates it
        # with numericality: {greater_than_or_equal_to: 0}, the bound valid_amount? enforces.
        def validate_fixed_charge_units(fixed_charge_override, index, fixed_charge_index)
          units = fixed_charge_override["units"]
          return if units.nil?
          return if ::Validators::DecimalAmountService.valid_amount?(units)

          add_error(
            field: plan_field(index, "overrides.fixedCharges.#{fixed_charge_index}.units"),
            error_code: "invalid_value"
          )
        end

        def validate_coupons
          coupons.each_with_index do |coupon_item, index|
            coupon = known_coupons_by_id[coupon_item["id"]]

            if coupon.nil?
              add_error(field: coupon_field(index, "id"), error_code: "coupon_not_found")
              next
            end

            validate_coupon_currency(coupon, index)
            validate_coupon_frequency(coupon, coupon_item, index)
            validate_coupon_snapshot(coupon, coupon_item, index) if scope == :approve
          end
        end

        def validate_coupon_currency(coupon, index)
          return unless coupon.fixed_amount?
          return if self.class.currency_list.exclude?(quote_version.currency)

          if coupon.amount_currency != quote_version.currency
            add_error(field: coupon_field(index, "id"), error_code: "currencies_does_not_match")
          end
        end

        # The snapshot type is required at approve while the amount checks below follow the live
        # coupon, so a coupon retyped since the quote was drafted must be flagged rather than
        # silently followed: it changes the negotiated discount.
        def validate_coupon_snapshot(coupon, coupon_item, index)
          if coupon_item.dig("payload", "type") != coupon.coupon_type
            add_error(field: coupon_field(index, "payload.type"), error_code: "coupon_type_does_not_match")
            return
          end

          if coupon.fixed_amount? && coupon_item.dig("payload", "amountCents").nil?
            add_error(field: coupon_field(index, "payload.amountCents"), error_code: "value_is_mandatory")
          end

          if coupon.percentage? && coupon_item.dig("payload", "percentageRate").nil?
            add_error(field: coupon_field(index, "payload.percentageRate"), error_code: "value_is_mandatory")
          end
        end

        # AppliedCoupon requires a positive frequency_duration when recurring, and
        # AppliedCoupons::CreateService falls back to the live coupon's own frequency and duration,
        # so overriding an already recurring coupon need not restate its duration. Only a coupon that
        # is recurring nowhere but in the quote, with no duration anywhere, cannot be applied.
        def validate_coupon_frequency(coupon, coupon_item, index)
          return unless scope == :approve
          return unless effective_coupon_value(coupon_item, "frequency", coupon.frequency) == "recurring"
          return unless effective_coupon_value(coupon_item, "frequencyDuration", coupon.frequency_duration).nil?

          section = (coupon_item.dig("overrides", "frequency") == "recurring") ? "overrides" : "payload"
          add_error(field: coupon_field(index, "#{section}.frequencyDuration"), error_code: "value_is_mandatory")
        end

        # Mirrors how the execution service resolves an overridden coupon value, then the fallback
        # AppliedCoupons::CreateService applies on the live coupon.
        def effective_coupon_value(coupon_item, field, coupon_value)
          coupon_item.dig("overrides", field) || coupon_item.dig("payload", field) || coupon_value
        end

        def validate_wallet_credits
          wallet_credits.each_with_index do |wallet_credit_item, index|
            payload = wallet_credit_item["payload"] || {}

            validate_wallet_credit_amounts(payload, index)
            validate_wallet_credit_currency(payload, index)
            validate_expiration(payload["expirationAt"], wallet_credit_field(index, "payload.expirationAt"))
            validate_recurring_rules(payload, index)
          end
        end

        # Unless the multi_currency flag is on, Wallets::CreateService forces the customer currency
        # onto the wallet, so a credit quoted in another currency is either silently ignored or
        # funds a wallet the customer never agreed to.
        def validate_wallet_credit_currency(payload, index)
          currency = payload["currency"]
          return if currency.nil?
          return if self.class.currency_list.exclude?(quote_version.currency)

          if currency != quote_version.currency
            add_error(field: wallet_credit_field(index, "payload.currency"), error_code: "currencies_does_not_match")
          end
        end

        # NOTE: futureness is only guaranteed at approval time. An order scheduled far enough
        # ahead can still reach execution with a past expiration, which Wallets::ValidateService
        # rejects then.
        def validate_expiration(expiration_at, field)
          return unless scope == :approve
          return if ::Validators::ExpirationDateValidator.valid?(expiration_at)

          add_error(field:, error_code: "invalid_date")
        end

        def validate_wallet_credit_amounts(payload, index)
          %w[paidCredits grantedCredits].each do |key|
            value = payload[key]
            next if value.nil?

            unless ::Validators::DecimalAmountService.valid_amount?(value)
              add_error(field: wallet_credit_field(index, "payload.#{key}"), error_code: "invalid_value")
            end
          end

          rate_amount = payload["rateAmount"]
          return if rate_amount.nil?

          unless ::Validators::DecimalAmountService.valid_positive_amount?(rate_amount)
            add_error(field: wallet_credit_field(index, "payload.rateAmount"), error_code: "invalid_value")
          end
        end

        def validate_recurring_rules(payload, wallet_credit_index)
          rules = payload["recurringTransactionRules"] || []

          rules.each_with_index do |rule, rule_index|
            validate_rule_trigger(rule, wallet_credit_index, rule_index)
            validate_rule_method(rule, wallet_credit_index, rule_index)
            validate_rule_grants_target_top_up(rule, wallet_credit_index, rule_index)
            validate_rule_credits(rule, wallet_credit_index, rule_index)
            validate_expiration(rule["expirationAt"], rule_field(wallet_credit_index, rule_index, "expirationAt"))
          end
        end

        def validate_rule_trigger(rule, wallet_credit_index, rule_index)
          case rule["trigger"]
          when "interval"
            if rule["interval"].nil?
              add_error(field: rule_field(wallet_credit_index, rule_index, "interval"), error_code: "value_is_mandatory")
            end
          when "threshold"
            threshold = rule["thresholdCredits"]

            if threshold.nil?
              add_error(field: rule_field(wallet_credit_index, rule_index, "thresholdCredits"), error_code: "value_is_mandatory")
            elsif !valid_decimal?(threshold)
              add_error(field: rule_field(wallet_credit_index, rule_index, "thresholdCredits"), error_code: "invalid_value")
            end
          end
        end

        def validate_rule_method(rule, wallet_credit_index, rule_index)
          return unless rule["method"] == "target"

          target = rule["targetOngoingBalance"]

          if target.nil?
            add_error(field: rule_field(wallet_credit_index, rule_index, "targetOngoingBalance"), error_code: "value_is_mandatory")
          elsif !valid_decimal?(target)
            add_error(field: rule_field(wallet_credit_index, rule_index, "targetOngoingBalance"), error_code: "invalid_value")
          elsif target_below_threshold?(rule, target)
            add_error(field: rule_field(wallet_credit_index, rule_index, "targetOngoingBalance"), error_code: "invalid_value")
          end
        end

        def target_below_threshold?(rule, target)
          rule["trigger"] == "threshold" &&
            valid_decimal?(rule["thresholdCredits"]) &&
            BigDecimal(target) < BigDecimal(rule["thresholdCredits"])
        end

        # Upstream only accepts the flag on a target rule, see
        # Wallets::RecurringTransactionRules::ValidateService#valid_grants_target_top_up?
        def validate_rule_grants_target_top_up(rule, wallet_credit_index, rule_index)
          return if rule["grantsTargetTopUp"].nil?
          return if rule["method"] == "target"

          add_error(
            field: rule_field(wallet_credit_index, rule_index, "grantsTargetTopUp"),
            error_code: "invalid_value"
          )
        end

        # NOTE: rule credits are deliberately sign-agnostic, mirroring upstream
        # Wallets::RecurringTransactionRules::ValidateService#valid_credits?. The wallet-level
        # amounts above use valid_amount? like Wallets::ValidateService, hence the difference.
        def validate_rule_credits(rule, wallet_credit_index, rule_index)
          %w[paidCredits grantedCredits].each do |key|
            value = rule[key]
            next if value.nil?

            unless valid_decimal?(value)
              add_error(field: rule_field(wallet_credit_index, rule_index, key), error_code: "invalid_value")
            end
          end
        end

        def valid_decimal?(value)
          ::Validators::DecimalAmountService.new(value).valid_decimal?
        end

        def plans
          billing_items["plans"] || []
        end

        def coupons
          billing_items["coupons"] || []
        end

        def wallet_credits
          billing_items["walletCredits"] || []
        end

        def plan_field(index, suffix)
          :"billing_items.plans.#{index}.#{suffix}"
        end

        def coupon_field(index, suffix)
          :"billing_items.coupons.#{index}.#{suffix}"
        end

        def wallet_credit_field(index, suffix)
          :"billing_items.walletCredits.#{index}.#{suffix}"
        end

        def rule_field(wallet_credit_index, rule_index, suffix)
          wallet_credit_field(wallet_credit_index, "payload.recurringTransactionRules.#{rule_index}.#{suffix}")
        end

        def known_plans_by_id
          @known_plans_by_id ||= quote_version
            .organization
            .plans
            .with_discarded
            .where(id: plans.map { |plan_item| plan_item["id"] })
            .index_by(&:id)
        end

        def known_charge_metric_codes
          @known_charge_metric_codes ||= Charge
            .with_discarded
            .joins(:billable_metric)
            .where(plan_id: known_plans_by_id.keys)
            .pluck(:plan_id, "billable_metrics.code")
            .to_set
        end

        def known_fixed_charge_add_on_codes
          @known_fixed_charge_add_on_codes ||= FixedCharge
            .with_discarded
            .joins(:add_on)
            .where(plan_id: known_plans_by_id.keys)
            .pluck(:plan_id, "add_ons.code")
            .to_set
        end

        def known_coupons_by_id
          @known_coupons_by_id ||= quote_version
            .organization
            .coupons
            .with_discarded
            .where(id: coupons.map { |coupon_item| coupon_item["id"] })
            .index_by(&:id)
        end
      end
    end
  end
end
