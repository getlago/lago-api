# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      class BusinessValidator < ::BaseValidator
        include Currencies
        include CurrencyValidation
        include BillingEntityValidation

        def initialize(result, quote_version:, billing_items:, scope:)
          @quote_version = quote_version
          @billing_items = billing_items
          @scope = scope

          super
        end

        # NOTE: payment terms are not validated yet, the quote-level field lands with LAGO-1529
        def valid?
          validate_currency
          validate_billing_entity
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

        # Subscriptions::ValidateService requires the ending date to be after today. NOTE:
        # futureness is only guaranteed at approval time. An order scheduled far enough ahead can
        # still reach execution with a past ending date, which that service rejects then.
        def validate_future_end_date(value, field)
          return unless scope == :approve

          end_date = Utils::Datetime.parse_iso8601(value)&.to_date
          return if end_date.nil?
          return if end_date > Time.current.to_date

          add_error(field:, error_code: "invalid_date")
        end

        def validate_plans
          plans.each_with_index do |plan_item, index|
            plan = known_plans_by_id[plan_item["id"]]

            if plan.nil?
              add_error(field: plan_field(index, "id"), error_code: "plan_not_found")
              next
            end

            validate_plan_currency(plan, plan_item, index)
            validate_minimum_commitment(plan, plan_item, index)
            validate_plan_dates(plan_item, index)
            validate_plan_payment_method(plan_item, index)
            validate_charge_overrides(plan_item, plan, index)
            validate_fixed_charge_overrides(plan_item, plan, index)
          end
        end

        # Whatever currency the plan is priced in ends up billed, so it has to be the deal's own.
        # A catalog plan priced elsewhere is quoted by overriding the currency, which
        # Plans::OverrideService applies to the plan it duplicates for the subscription.
        def validate_plan_currency(plan, plan_item, index)
          return if self.class.currency_list.exclude?(quote_version.currency)

          if effective_plan_currency(plan, plan_item) != quote_version.currency
            add_error(field: plan_field(index, "id"), error_code: "currencies_does_not_match")
          end
        end

        def effective_plan_currency(plan, plan_item)
          plan_item.dig("overrides", "amountCurrency").presence || plan.amount_currency
        end

        # Plans::OverrideService builds a fresh Commitment rather than duplicating the plan's own,
        # and Commitment rejects a nil amount, so the amount has to reach it from one side or the
        # other. NOTE: the amount resolved here is the plan's, so the subscription_creation
        # execution service must pass it down when the override omits it.
        def validate_minimum_commitment(plan, plan_item, index)
          return unless scope == :approve

          minimum_commitment = plan_item.dig("overrides", "minimumCommitment")
          return if minimum_commitment.nil?
          return unless (minimum_commitment["amountCents"] || plan.minimum_commitment&.amount_cents).nil?

          add_error(
            field: plan_field(index, "overrides.minimumCommitment.amountCents"),
            error_code: "value_is_mandatory"
          )
        end

        # Plans::OverrideService matches overrides by charge id and silently ignores an id it
        # cannot find, which would bill the catalog price instead of the negotiated one. So the
        # id the execution flow will use is resolved here, from the payload snapshot, and must
        # still exist on the plan.
        def validate_charge_overrides(plan_item, plan, index)
          charge_overrides(plan_item).each_with_index do |charge_override, charge_index|
            field = plan_field(index, "overrides.charges.#{charge_index}.billableMetricCode")
            snapshots = snapshot_charges(plan_item).each_with_index.select do |snapshot, _|
              snapshot.dig("billableMetric", "code") == charge_override["billableMetricCode"]
            end

            next add_error(field:, error_code: "charge_not_found") if snapshots.empty?
            next add_error(field:, error_code: "ambiguous_charge_override") if snapshots.count > 1

            snapshot, snapshot_index = snapshots.first
            charge = plan.charges.find { |plan_charge| plan_charge.id == snapshot["id"] }

            next add_error(field:, error_code: "charge_not_found") if charge.nil?

            validate_charge_model(charge_override, charge, index, charge_index)
            validate_snapshot_charge_model(
              snapshot,
              charge,
              plan_field(index, "payload.charges.#{snapshot_index}.chargeModel")
            )
            # The negotiated properties only mean something against the model they were drafted
            # for, and a model that moved is already reported above.
            next if model_changed?(charge_override["chargeModel"], charge) ||
              model_changed?(snapshot["chargeModel"], charge)

            validate_charge_properties(charge_override, charge, index, charge_index)
            validate_charge_min_amount(charge_override, charge, index, charge_index)
          end
        end

        # The snapshot pins the charge model the approver was looking at, and an override omitting
        # chargeModel would otherwise let the catalog drift away from it unnoticed, landing the
        # negotiated properties on another model.
        def validate_snapshot_charge_model(snapshot, charge, field)
          return unless model_changed?(snapshot["chargeModel"], charge)

          add_error(field:, error_code: "charge_model_changed")
        end

        # Charges::OverrideService cannot switch a charge model and ignores the key, so properties
        # negotiated for another model would land on the catalog one.
        def validate_charge_model(charge_override, charge, index, charge_index)
          return unless model_changed?(charge_override["chargeModel"], charge)

          add_error(
            field: plan_field(index, "overrides.charges.#{charge_index}.chargeModel"),
            error_code: "cannot_override_charge_model"
          )
        end

        # A quote that pinned no model follows whatever the catalog holds.
        def model_changed?(quoted_charge_model, chargeable)
          return false if quoted_charge_model.nil?

          quoted_charge_model != chargeable.charge_model
        end

        def validate_charge_properties(charge_override, charge, index, charge_index)
          properties = charge_override["properties"]
          return if properties.nil?

          field = plan_field(index, "overrides.charges.#{charge_index}.properties")
          validate_properties(charge, properties, field)
        # The model validators below assume a hash shaped for their charge model and raise on
        # anything else, while a quoted payload is free-form.
        rescue
          add_error(field:, error_code: "invalid_value")
        end

        # Charge#validate_min_amount_cents refuses a minimum on a charge billed in advance, and
        # Plans::OverrideService swallows that failure the same way.
        def validate_charge_min_amount(charge_override, charge, index, charge_index)
          return unless charge.pay_in_advance?
          return unless charge_override["minAmountCents"].to_i.positive?

          add_error(
            field: plan_field(index, "overrides.charges.#{charge_index}.minAmountCents"),
            error_code: "not_compatible_with_pay_in_advance"
          )
        end

        def validate_fixed_charge_overrides(plan_item, plan, index)
          fixed_charge_overrides(plan_item).each_with_index do |fixed_charge_override, fixed_charge_index|
            validate_fixed_charge_units(fixed_charge_override, index, fixed_charge_index)

            field = plan_field(index, "overrides.fixedCharges.#{fixed_charge_index}.addOnCode")
            snapshots = snapshot_fixed_charges(plan_item).each_with_index.select do |snapshot, _|
              snapshot.dig("addOn", "code") == fixed_charge_override["addOnCode"]
            end

            next add_error(field:, error_code: "fixed_charge_not_found") if snapshots.empty?
            next add_error(field:, error_code: "ambiguous_fixed_charge_override") if snapshots.count > 1

            snapshot, snapshot_index = snapshots.first
            fixed_charge = plan.fixed_charges.find { |plan_fixed_charge| plan_fixed_charge.id == snapshot["id"] }

            next add_error(field:, error_code: "fixed_charge_not_found") if fixed_charge.nil?

            validate_snapshot_fixed_charge_model(
              snapshot,
              fixed_charge,
              plan_field(index, "payload.fixedCharges.#{snapshot_index}.chargeModel")
            )
            next if model_changed?(snapshot["chargeModel"], fixed_charge)

            validate_fixed_charge_properties(fixed_charge_override, fixed_charge, index, fixed_charge_index)
          end
        end

        # FixedCharges::OverrideService does refuse a model switch, but Plans::OverrideService never
        # checks its result and the override carries no model of its own, so the snapshot is the only
        # place the approved model survives.
        def validate_snapshot_fixed_charge_model(snapshot, fixed_charge, field)
          return unless model_changed?(snapshot["chargeModel"], fixed_charge)

          add_error(field:, error_code: "fixed_charge_model_changed")
        end

        # FixedCharges::OverrideService slices the properties down to the keys its charge model knows
        # before saving, and FixedCharge requires them to be present, so an override drafted for
        # another model filters down to nothing and takes the fixed charge with it.
        def validate_fixed_charge_properties(fixed_charge_override, fixed_charge, index, fixed_charge_index)
          properties = fixed_charge_override["properties"]
          return if properties.nil?

          field = plan_field(index, "overrides.fixedCharges.#{fixed_charge_index}.properties")
          filtered = ChargeModels::FilterPropertiesService
            .call(chargeable: fixed_charge, properties: properties.presence)
            .properties

          return add_error(field:, error_code: "invalid_value") if filtered.blank?

          validate_properties(fixed_charge, filtered, field)
        # Neither the filter nor the model validators tolerate a hash shaped for something else,
        # while a quoted payload is free-form.
        rescue
          add_error(field:, error_code: "invalid_value")
        end

        # Plans::OverrideService calls the two override services without raise_if_error! and both
        # rescue RecordInvalid, so properties the charge model rejects drop the charge from the
        # override plan instead of failing execution: the subscription would then bill nothing at all
        # for it. These are the validators the models themselves run.
        def validate_properties(chargeable, properties, field)
          validator = ChargePropertiesValidation::PROPERTIES_VALIDATORS
            .fetch(chargeable.charge_model.to_sym, ::Charges::Validators::BaseService)
            .new(charge: chargeable, properties:)

          return if validator.valid?

          validator.result.error.messages.each do |key, error_codes|
            error_codes.each { add_error(field: :"#{field}.#{key}", error_code: it) }
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

        # Subscriptions::ValidateService requires the pair, compared as dates, to be strictly
        # increasing. An open-ended deal is legitimate, the subscription simply carries no ending
        # date, so only a plan stating both sides has a range to check.
        # A plan stating no start date is left alone: Subscriptions::CreateService defaults the
        # subscription date to the moment it runs, so the deal simply starts on execution.
        def validate_plan_dates(plan_item, index)
          start_date = plan_item.dig("payload", "startDate")
          end_date = plan_item.dig("payload", "endDate")

          valid_start = validate_plan_date(start_date, plan_field(index, "payload.startDate"))
          valid_end = validate_plan_date(end_date, plan_field(index, "payload.endDate"))
          return unless valid_start && valid_end

          validate_future_end_date(end_date, plan_field(index, "payload.endDate"))

          effective_start = effective_date(start_date)
          effective_end = effective_date(end_date)
          return if effective_start.nil? || effective_end.nil?
          return if effective_end > effective_start

          add_error(field: plan_field(index, "payload.endDate"), error_code: "invalid_date_range")
        end

        # Same ISO 8601 check as Subscriptions::ValidateService, the service these dates feed.
        def validate_plan_date(value, field)
          return true if value.nil?
          return true if Utils::Datetime.valid_format?(value)

          add_error(field:, error_code: "invalid_date")
          false
        end

        # Same parsing as Subscriptions::ValidateService: the payload carries ISO 8601 strings and
        # the service compares them as dates.
        def effective_date(value)
          Utils::Datetime.parse_iso8601(value)&.to_date
        end

        # Subscriptions::CreateService resolves the payment method by id and organization only, so
        # ownership is checked here: another customer's method would otherwise be attached.
        def validate_plan_payment_method(plan_item, index)
          payment_method_id = plan_item.dig("payload", "paymentMethodId")
          return if payment_method_id.nil?
          return if known_payment_method_ids.include?(payment_method_id)

          add_error(field: plan_field(index, "payload.paymentMethodId"), error_code: "payment_method_not_found")
        end

        def validate_coupons
          earlier_coupons = []

          coupons.each_with_index do |coupon_item, index|
            coupon = known_coupons_by_id[coupon_item["id"]]

            if coupon.nil?
              add_error(field: coupon_field(index, "id"), error_code: "coupon_not_found")
              next
            end

            validate_coupon_currency(coupon, coupon_item, index)
            validate_coupon_frequency(coupon, coupon_item, index)
            validate_coupon_preconditions(coupon, earlier_coupons, index)
            validate_coupon_snapshot(coupon, coupon_item, index) if scope == :approve

            earlier_coupons << coupon
          end
        end

        # AppliedCoupons::CreateService refuses a non-reusable coupon the customer already carries and
        # a limited coupon overlapping one already applied. The deal applies its coupons one by one,
        # so the first application is what makes a second one fail, halfway through execution.
        # NOTE: the customer's own applied coupons are deliberately not checked here, that state can
        # change between approval and execution.
        def validate_coupon_preconditions(coupon, earlier_coupons, index)
          if !coupon.reusable? && earlier_coupons.any? { |earlier| earlier.id == coupon.id }
            add_error(field: coupon_field(index, "id"), error_code: "coupon_is_not_reusable")
          end

          return unless limited?(coupon)
          return if earlier_coupons.none? { |earlier| overlapping_limitations?(coupon, earlier) }

          add_error(field: coupon_field(index, "id"), error_code: "plan_overlapping")
        end

        def limited?(coupon)
          coupon.limited_plans? || coupon.limited_billable_metrics?
        end

        # The four comparisons AppliedCoupons::CreateService makes: plans against plans, metrics
        # against metrics, and each against the other through the charges connecting them.
        def overlapping_limitations?(coupon, earlier)
          plan_ids = target_ids(coupon, :plan_id)
          metric_ids = target_ids(coupon, :billable_metric_id)
          earlier_plan_ids = target_ids(earlier, :plan_id)
          earlier_metric_ids = target_ids(earlier, :billable_metric_id)

          plan_ids.intersect?(earlier_plan_ids) ||
            metric_ids.intersect?(earlier_metric_ids) ||
            earlier_plan_ids.intersect?(plans_charging(metric_ids)) ||
            earlier_metric_ids.intersect?(metrics_charged_by(plan_ids))
        end

        def target_ids(coupon, attribute)
          coupon.coupon_targets.filter_map(&attribute)
        end

        def plans_charging(metric_ids)
          metric_ids.flat_map { plans_by_metric_id[it] || [] }
        end

        def metrics_charged_by(plan_ids)
          plan_ids.flat_map { metrics_by_plan_id[it] || [] }
        end

        # The charges connecting the two limitation kinds, resolved once for every coupon the quote
        # carries rather than once per pair compared.
        def plans_by_metric_id
          @plans_by_metric_id ||= Charge
            .joins(:billable_metric)
            .where(billable_metric: {id: quoted_target_ids(:billable_metric_id)})
            .pluck(:billable_metric_id, :plan_id)
            .group_by(&:first)
            .transform_values { |rows| rows.map(&:last) }
        end

        def metrics_by_plan_id
          @metrics_by_plan_id ||= Charge
            .joins(:plan)
            .where(plan: {id: quoted_target_ids(:plan_id)})
            .pluck(:plan_id, :billable_metric_id)
            .group_by(&:first)
            .transform_values { |rows| rows.map(&:last) }
        end

        def quoted_target_ids(attribute)
          known_coupons_by_id.each_value.flat_map { |coupon| target_ids(coupon, attribute) }.uniq
        end

        # The coupon is applied in whatever currency it carries, so it has to be the deal's own. A
        # catalog coupon priced elsewhere is quoted by overriding the currency, which
        # AppliedCoupons::CreateService applies to the coupon it grants.
        def validate_coupon_currency(coupon, coupon_item, index)
          return unless coupon.fixed_amount?
          return if self.class.currency_list.exclude?(quote_version.currency)

          if effective_coupon_currency(coupon, coupon_item) != quote_version.currency
            add_error(field: coupon_field(index, "id"), error_code: "currencies_does_not_match")
          end
        end

        def effective_coupon_currency(coupon, coupon_item)
          coupon_item.dig("overrides", "amountCurrency").presence || coupon.amount_currency
        end

        # The snapshot type is required at approve while the amount checks below follow the live
        # coupon, so a coupon retyped since the quote was drafted must be flagged rather than
        # silently followed: it changes the negotiated discount.
        def validate_coupon_snapshot(coupon, coupon_item, index)
          if coupon_item.dig("payload", "type") != coupon.coupon_type
            add_error(field: coupon_field(index, "payload.type"), error_code: "coupon_type_does_not_match")
            return
          end

          if coupon.fixed_amount? && quoted_coupon_value(coupon_item, "amountCents").nil?
            add_error(field: coupon_field(index, "payload.amountCents"), error_code: "value_is_mandatory")
          end

          if coupon.percentage? && quoted_coupon_value(coupon_item, "percentageRate").nil?
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

        # A negotiated value overrides the catalog snapshot it was drafted from, the way the
        # execution services resolve a quoted value, see Orders::OneOff::ExecuteService.
        def quoted_coupon_value(coupon_item, field)
          coupon_item.dig("overrides", field) || coupon_item.dig("payload", field)
        end

        # Adds the fallback AppliedCoupons::CreateService applies on the live coupon, for the
        # values it defaults rather than requires.
        def effective_coupon_value(coupon_item, field, coupon_value)
          quoted_coupon_value(coupon_item, field) || coupon_value
        end

        def validate_wallet_credits
          wallet_credits.each_with_index do |wallet_credit_item, index|
            payload = wallet_credit_item["payload"] || {}

            validate_wallet_credit_amounts(payload, index)
            validate_wallet_credit_currency(payload, index)
            validate_wallet_credit_applies_to(payload, index)
            validate_expiration(payload["expirationAt"], wallet_credit_field(index, "payload.expirationAt"))
            validate_recurring_rules(payload, index)
          end
        end

        # Outside api context Wallets::CreateService resolves metric limitations by id, so a code
        # that does not resolve means the wallet is created without its limitation instead of
        # failing.
        def validate_wallet_credit_applies_to(payload, index)
          codes = Array(payload.dig("appliesTo", "billableMetricCodes"))
          return if codes.empty?
          return if (codes - known_billable_metric_codes).empty?

          add_error(
            field: wallet_credit_field(index, "payload.appliesTo.billableMetricCodes"),
            error_code: "billable_metric_not_found"
          )
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

        def charge_overrides(plan_item)
          Array(plan_item.dig("overrides", "charges"))
        end

        def fixed_charge_overrides(plan_item)
          Array(plan_item.dig("overrides", "fixedCharges"))
        end

        def snapshot_charges(plan_item)
          Array(plan_item.dig("payload", "charges"))
        end

        def snapshot_fixed_charges(plan_item)
          Array(plan_item.dig("payload", "fixedCharges"))
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
            .includes(:charges, :fixed_charges, :minimum_commitment)
            .where(id: plans.map { |plan_item| plan_item["id"] })
            .index_by(&:id)
        end

        def known_payment_method_ids
          @known_payment_method_ids ||= quote_version
            .quote
            .customer
            .payment_methods
            .where(id: plans.filter_map { |plan_item| plan_item.dig("payload", "paymentMethodId") })
            .pluck(:id)
            .to_set
        end

        def known_billable_metric_codes
          @known_billable_metric_codes ||= quote_version
            .organization
            .billable_metrics
            .where(code: wallet_credits.flat_map { |item| Array(item.dig("payload", "appliesTo", "billableMetricCodes")) })
            .pluck(:code)
        end

        def known_coupons_by_id
          @known_coupons_by_id ||= quote_version
            .organization
            .coupons
            .with_discarded
            .includes(:coupon_targets)
            .where(id: coupons.map { |coupon_item| coupon_item["id"] })
            .index_by(&:id)
        end
      end
    end
  end
end
