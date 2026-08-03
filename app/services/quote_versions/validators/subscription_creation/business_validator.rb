# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      class BusinessValidator < ::BaseValidator
        include Currencies

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
          validate_wallets

          if errors?
            result.validation_failure!(errors:)
            return false
          end

          true
        end

        private

        attr_reader :quote_version, :billing_items, :scope

        def validate_currency
          currency = quote_version.currency

          if currency.blank?
            add_error(field: :currency, error_code: "value_is_mandatory") if scope == :approve
          elsif self.class.currency_list.exclude?(currency)
            add_error(field: :currency, error_code: "invalid_currency")
          end
        end

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
            unless known_plan_ids.include?(plan_item["id"])
              add_error(field: plan_field(index, "id"), error_code: "plan_not_found")
              next
            end

            validate_charge_overrides(plan_item, index)
            validate_fixed_charge_overrides(plan_item, index)
          end
        end

        def validate_charge_overrides(plan_item, index)
          charge_overrides = plan_item.dig("overrides", "charges") || []

          charge_overrides.each_with_index do |charge_override, charge_index|
            unless known_charge_keys.include?([plan_item["id"], charge_override["id"]])
              add_error(
                field: plan_field(index, "overrides.charges.#{charge_index}.id"),
                error_code: "charge_not_found"
              )
            end
          end
        end

        def validate_fixed_charge_overrides(plan_item, index)
          fixed_charge_overrides = plan_item.dig("overrides", "fixedCharges") || []

          fixed_charge_overrides.each_with_index do |fixed_charge_override, fixed_charge_index|
            unless known_fixed_charge_keys.include?([plan_item["id"], fixed_charge_override["id"]])
              add_error(
                field: plan_field(index, "overrides.fixedCharges.#{fixed_charge_index}.id"),
                error_code: "fixed_charge_not_found"
              )
            end
          end
        end

        def validate_coupons
          coupons.each_with_index do |coupon_item, index|
            coupon = known_coupons_by_id[coupon_item["id"]]

            if coupon.nil?
              add_error(field: coupon_field(index, "id"), error_code: "coupon_not_found")
              next
            end

            validate_coupon_currency(coupon, index)
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

        def validate_coupon_snapshot(coupon, coupon_item, index)
          if coupon.fixed_amount? && coupon_item.dig("payload", "amountCents").nil?
            add_error(field: coupon_field(index, "payload.amountCents"), error_code: "value_is_mandatory")
          end

          if coupon.percentage? && coupon_item.dig("payload", "percentageRate").nil?
            add_error(field: coupon_field(index, "payload.percentageRate"), error_code: "value_is_mandatory")
          end
        end

        def validate_wallets
          wallets.each_with_index do |wallet_item, index|
            payload = wallet_item["payload"] || {}

            validate_wallet_amounts(payload, index)
            validate_recurring_rules(payload, index)
          end
        end

        def validate_wallet_amounts(payload, index)
          %w[paidCredits grantedCredits].each do |key|
            value = payload[key]
            next if value.nil?

            unless ::Validators::DecimalAmountService.valid_amount?(value)
              add_error(field: wallet_field(index, "payload.#{key}"), error_code: "invalid_value")
            end
          end

          rate_amount = payload["rateAmount"]
          return if rate_amount.nil?

          unless ::Validators::DecimalAmountService.valid_positive_amount?(rate_amount)
            add_error(field: wallet_field(index, "payload.rateAmount"), error_code: "invalid_value")
          end
        end

        def validate_recurring_rules(payload, wallet_index)
          rules = payload["recurringTransactionRules"] || []

          rules.each_with_index do |rule, rule_index|
            validate_rule_trigger(rule, wallet_index, rule_index)
            validate_rule_method(rule, wallet_index, rule_index)
            validate_rule_credits(rule, wallet_index, rule_index)
          end
        end

        def validate_rule_trigger(rule, wallet_index, rule_index)
          case rule["trigger"]
          when "interval"
            if rule["interval"].nil?
              add_error(field: rule_field(wallet_index, rule_index, "interval"), error_code: "value_is_mandatory")
            end
          when "threshold"
            threshold = rule["thresholdCredits"]

            if threshold.nil?
              add_error(field: rule_field(wallet_index, rule_index, "thresholdCredits"), error_code: "value_is_mandatory")
            elsif !valid_decimal?(threshold)
              add_error(field: rule_field(wallet_index, rule_index, "thresholdCredits"), error_code: "invalid_value")
            end
          end
        end

        def validate_rule_method(rule, wallet_index, rule_index)
          return unless rule["method"] == "target"

          target = rule["targetOngoingBalance"]

          if target.nil?
            add_error(field: rule_field(wallet_index, rule_index, "targetOngoingBalance"), error_code: "value_is_mandatory")
          elsif !valid_decimal?(target)
            add_error(field: rule_field(wallet_index, rule_index, "targetOngoingBalance"), error_code: "invalid_value")
          elsif target_below_threshold?(rule, target)
            add_error(field: rule_field(wallet_index, rule_index, "targetOngoingBalance"), error_code: "invalid_value")
          end
        end

        def target_below_threshold?(rule, target)
          rule["trigger"] == "threshold" &&
            valid_decimal?(rule["thresholdCredits"]) &&
            BigDecimal(target) < BigDecimal(rule["thresholdCredits"])
        end

        def validate_rule_credits(rule, wallet_index, rule_index)
          %w[paidCredits grantedCredits].each do |key|
            value = rule[key]
            next if value.nil?

            unless valid_decimal?(value)
              add_error(field: rule_field(wallet_index, rule_index, key), error_code: "invalid_value")
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

        def wallets
          billing_items["wallets"] || []
        end

        def plan_field(index, suffix)
          :"billing_items.plans.#{index}.#{suffix}"
        end

        def coupon_field(index, suffix)
          :"billing_items.coupons.#{index}.#{suffix}"
        end

        def wallet_field(index, suffix)
          :"billing_items.wallets.#{index}.#{suffix}"
        end

        def rule_field(wallet_index, rule_index, suffix)
          wallet_field(wallet_index, "payload.recurringTransactionRules.#{rule_index}.#{suffix}")
        end

        def known_plan_ids
          @known_plan_ids ||= quote_version
            .organization
            .plans
            .with_discarded
            .where(id: plans.map { |plan_item| plan_item["id"] })
            .pluck(:id)
            .to_set
        end

        def known_charge_keys
          @known_charge_keys ||= Charge
            .with_discarded
            .where(
              plan_id: known_plan_ids.to_a,
              id: plans.flat_map { |plan_item| (plan_item.dig("overrides", "charges") || []).map { |charge_override| charge_override["id"] } }
            )
            .pluck(:plan_id, :id)
            .to_set
        end

        def known_fixed_charge_keys
          @known_fixed_charge_keys ||= FixedCharge
            .with_discarded
            .where(
              plan_id: known_plan_ids.to_a,
              id: plans.flat_map { |plan_item| (plan_item.dig("overrides", "fixedCharges") || []).map { |fixed_charge_override| fixed_charge_override["id"] } }
            )
            .pluck(:plan_id, :id)
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
