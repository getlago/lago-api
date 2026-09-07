# frozen_string_literal: true

# Interprets one row of the golden billing matrix: materialises its setup, walks its timeline,
# asserts its expectations. The row format is defined by spec/scenarios/golden/schema.json.
#
# Every API interaction goes through ScenariosHelper, so the golden suite exercises the same request
# path as the rest of spec/scenarios and inherits its enqueued-job draining.
module GoldenRunner
  # Fees are matched by content, not position: the serializer's ordering is an implementation
  # detail. Identity keys only, so a value mismatch reports as one rather than as "no fee matched".
  FEE_MATCH_KEYS = %w[fee_type item_code item_type from_date to_date].freeze

  def run_golden_row(row)
    ctx = {metrics: {}, add_ons: {}, plans: {}, plan: nil, customer: nil, subscription: nil}

    catch(:golden_row_done) do
      travel_to(golden_time(golden_setup_time(row))) do
        materialise_golden_setup(row, ctx)
      end
      walk_golden_timeline(row, ctx) if row["timeline"].present?
      assert_golden_expectations(row, ctx)
    end
  end

  private

  def golden_setup_time(row)
    row["at"] || row.dig("timeline", 0, "at") ||
      raise(ArgumentError, "golden row #{row["id"]}: needs either `at` or a `timeline`")
  end

  def golden_time(value)
    GoldenComparison.parse_time(value)
  end

  def golden_currency(row)
    row.dig("setup", "plan", "amount_currency") || row.dig("setup", "customer", "currency") || "EUR"
  end

  # ---------------------------------------------------------------- setup

  def materialise_golden_setup(row, ctx)
    setup = row["setup"] || {}
    failing = row.dig("expect", "error")

    apply_golden_organization(setup["organization"]) if setup["organization"]
    golden_assert_error_stage_supported(failing)
    (setup["taxes"] || []).each { |tax| create_golden_tax(tax, ctx) }
    (setup["add_ons"] || []).each { |add_on| create_golden_add_on(add_on, ctx) }
    (setup["metrics"] || []).each { |metric| create_golden_metric(metric, ctx, failing) }
    create_golden_plan(setup, ctx, failing) if setup["plan"]
    (setup["plans"] || []).each { |plan| create_golden_extra_plan(plan, ctx) }
    (setup["fixed_charges"] || []).each { |fixed_charge| create_golden_fixed_charge(fixed_charge, ctx) }
    create_golden_customer(setup, ctx, row)
    (setup["coupons"] || []).each { |coupon| apply_golden_coupon(coupon, ctx) }
    (setup["wallets"] || []).each { |wallet| create_golden_wallet(wallet, ctx) }
  end

  # The schema permits more error stages than the interpreter implements, and an unimplemented one
  # used to make the row pass while asserting nothing. `usage` is the only stage outside setup: it is
  # the GET current_usage that a fetch_current_usage step performs.
  SUPPORTED_ERROR_STAGES = %w[metric plan charge subscription usage].freeze

  def golden_assert_error_stage_supported(failing)
    return unless failing

    stage = failing["stage"]
    return if SUPPORTED_ERROR_STAGES.include?(stage)

    raise ArgumentError,
      "golden row: expect.error.stage #{stage.inspect} is not implemented by the interpreter " \
      "(supported: #{SUPPORTED_ERROR_STAGES.join(", ")}). The row would otherwise pass without " \
      "asserting anything."
  end

  # custom_agg metrics are gated on organization.custom_aggregation, a separate switch from
  # License.premium?.
  def apply_golden_organization(attributes)
    permitted = attributes.slice("custom_aggregation", "premium_integrations")
    permitted["default_currency"] = attributes["currency"] if attributes.key?("currency")
    organization.update!(permitted.symbolize_keys) if permitted.any?
  end

  # Braces are load-bearing on the ScenariosHelper calls below: the helpers take `(params, **kwargs)`,
  # so bare keyword syntax is swallowed by kwargs and the required argument goes missing.
  def create_golden_tax(tax, ctx)
    create_tax({
      name: tax["name"] || tax["code"],
      code: tax["code"],
      rate: tax["rate"],
      applied_to_organization: tax.fetch("applied_to_organization", true)
    })
    (ctx[:taxes] ||= []) << tax["code"]
  end

  def create_golden_add_on(add_on, ctx)
    params = add_on.symbolize_keys
    params[:name] ||= add_on["code"]
    params[:amount_currency] ||= "EUR"
    ctx[:add_ons][add_on["code"]] = create_add_on(params).fetch(:add_on)
  end

  def create_golden_extra_plan(plan, ctx)
    ctx[:plans][plan["code"]] = create_golden_plan({"plan" => plan, "charges" => plan["charges"]}, ctx, nil, primary: false)
  end

  def create_golden_fixed_charge(fixed_charge, ctx)
    add_on = ctx[:add_ons][fixed_charge["add_on_code"]]
    unless add_on
      raise ArgumentError,
        "golden row: fixed charge references add-on #{fixed_charge["add_on_code"].inspect} which the " \
        "row does not declare; declared add-ons are #{ctx[:add_ons].keys.inspect}"
    end

    params = fixed_charge.except("add_on_code").symbolize_keys
    params[:add_on_id] = add_on[:lago_id]
    params[:code] ||= fixed_charge["add_on_code"]
    create_plan_fixed_charge(Plan.find(ctx[:plan][:lago_id]), params)
  end

  def create_golden_metric(metric, ctx, failing)
    params = metric.except("code").symbolize_keys
    params[:code] = metric["code"]
    params[:name] ||= metric["code"]

    if failing && failing["stage"] == "metric"
      response = create_metric(params, raise_on_error: false)
      assert_golden_error(failing, response)
    end

    ctx[:metrics][metric["code"]] = create_metric(params).fetch(:billable_metric)
  end

  def create_golden_plan(setup, ctx, failing, primary: true)
    plan = setup["plan"]
    code = plan["code"] || "golden_plan"
    params = {
      name: plan["name"] || code,
      code: code,
      # key?, not ||: an explicit null interval is a rejection row and must reach the payload.
      interval: plan.key?("interval") ? plan["interval"] : "monthly",
      amount_cents: plan.fetch("amount_cents", 0),
      amount_currency: golden_currency("setup" => setup),
      pay_in_advance: plan.fetch("pay_in_advance", false),
      charges: (setup["charges"] || []).map { |charge| golden_charge_params(charge, ctx) }
    }
    params[:trial_period] = plan["trial_period"] if plan.key?("trial_period")
    params[:bill_charges_monthly] = plan["bill_charges_monthly"] if plan.key?("bill_charges_monthly")
    params[:tax_codes] = plan["tax_codes"] if plan.key?("tax_codes")
    params[:minimum_commitment] = plan["minimum_commitment"].symbolize_keys if plan["minimum_commitment"]
    params[:usage_thresholds] = plan["usage_thresholds"].map(&:symbolize_keys) if plan["usage_thresholds"]

    # Charges are inlined on plan creation, so a charge-level rejection surfaces here.
    if failing && %w[plan charge].include?(failing["stage"])
      response = create_plan(params, raise_on_error: false)
      assert_golden_error(failing, response)
    end

    created = create_plan(params).fetch(:plan)
    ctx[:plan] = created if primary
    ctx[:plans][created[:code]] = created
    created
  end

  def golden_charge_params(charge, ctx)
    metric = ctx[:metrics][charge["billable_metric_code"]]
    unless metric
      raise ArgumentError,
        "golden row: charge references unknown metric #{charge["billable_metric_code"].inspect}; " \
        "declared metrics are #{ctx[:metrics].keys.inspect}"
    end

    params = {
      billable_metric_id: metric[:lago_id],
      charge_model: charge["charge_model"],
      properties: charge["properties"] || {}
    }
    # `accepts_target_wallet` needs `premium: true` AND
    # `setup.organization.premium_integrations: [events_targeting_wallets]`. Both gates are silent:
    # without them the charge comes back with the flag false and its fees carry no target_wallet_code,
    # which is the tag wallet limitation matches on.
    %w[code invoiceable prorated pay_in_advance regroup_paid_fees min_amount_cents tax_codes
      accepts_target_wallet].each do |key|
      params[key.to_sym] = charge[key] if charge.key?(key)
    end
    params[:filters] = charge["filters"].map(&:symbolize_keys) if charge["filters"]
    params
  end

  # Flat in a row, nested in the request: invoice_grace_period and document_locale live under
  # billing_configuration, and sent at the top level they are dropped by strong params with HTTP 200.
  NESTED_CUSTOMER_KEYS = %w[invoice_grace_period document_locale].freeze
  FLAT_CUSTOMER_KEYS = %w[timezone country tax_codes net_payment_term finalize_zero_amount_invoice].freeze

  def golden_customer_params(attributes)
    params = FLAT_CUSTOMER_KEYS.each_with_object({}) do |key, flat|
      flat[key.to_sym] = attributes[key] if attributes.key?(key)
    end

    billing_configuration = NESTED_CUSTOMER_KEYS.each_with_object({}) do |key, nested|
      nested[key.to_sym] = attributes[key] if attributes.key?(key)
    end
    params[:billing_configuration] = billing_configuration if billing_configuration.any?

    params
  end

  def create_golden_customer(setup, ctx, row)
    customer = setup["customer"] || {}
    params = {
      external_id: customer["external_id"] || "golden_customer",
      name: customer["name"] || "Golden Customer",
      currency: customer["currency"] || golden_currency(row)
    }
    params.merge!(golden_customer_params(customer))

    ctx[:customer] = create_or_update_customer(params).fetch(:customer)
  end

  def apply_golden_coupon(coupon, ctx)
    params = coupon.except("frequency_duration_remaining").symbolize_keys
    params[:name] ||= params[:code]
    create_coupon(params)
    apply_coupon({external_customer_id: ctx[:customer][:external_id], coupon_code: coupon["code"]})
    (ctx[:coupons] ||= []) << coupon["code"]
  end

  def create_golden_wallet(wallet, ctx)
    create_wallet(wallet.symbolize_keys.merge(external_customer_id: ctx[:customer][:external_id]))
  end

  # ---------------------------------------------------------------- timeline

  def walk_golden_timeline(row, ctx)
    row["timeline"].each_with_index do |step, index|
      travel_to(golden_time(step["at"])) do
        perform_golden_step(step, ctx, row)
      end
    rescue => e
      raise e.class, "golden row #{row["id"]}: step #{index + 1} (#{step["do"]} at #{step["at"]}) failed: #{e.message}", e.backtrace
    end
  end

  def perform_golden_step(step, ctx, row)
    case step["do"]
    when "create_subscription" then golden_create_subscription(step, ctx, row)
    when "ingest_events" then golden_ingest_events(step, ctx)
    when "pay_fees" then golden_pay_fees(ctx)
    when "pay_invoice" then golden_pay_invoice(step, ctx)
    when "create_credit_note" then golden_create_credit_note(step, ctx)
    when "create_one_off_invoice" then golden_create_one_off_invoice(step, ctx)
    when "preview_invoice" then golden_preview_invoice(step, ctx)
    when "update_plan_charge" then golden_update_plan_charge(step, ctx)
    when "update_plan_fixed_charge" then golden_update_plan_fixed_charge(step, ctx)
    when "update_subscription_fixed_charge" then golden_update_subscription_fixed_charge(step, ctx)
    when "update_subscription" then golden_update_subscription(step, ctx)
    when "update_plan" then golden_update_plan(step, ctx)
    when "delete_metric" then golden_delete_metric(step, ctx)
    when "update_tax" then golden_update_tax(step, ctx)
    when "update_coupon" then golden_update_coupon(step, ctx)
    when "update_customer" then golden_update_customer(step, ctx)
    when "top_up_wallet" then golden_top_up_wallet(step, ctx)
    when "terminate_subscription" then terminate_subscription(ctx[:subscription], params: (step["params"] || {}).symbolize_keys)
    when "fetch_current_usage" then golden_snapshot_usage(ctx, row)
    when "perform_billing" then perform_billing
    when "perform_usage_update" then perform_usage_update
    when "perform_invoices_refresh" then perform_invoices_refresh
    when "perform_finalize_refresh" then perform_finalize_refresh
    when "perform_wallet_refresh" then perform_wallet_refresh
    when "perform_interval_wallet_top_ups" then perform_interval_wallet_top_ups
    when "perform_ended_subscriptions_termination" then perform_ended_subscriptions_termination
    when "perform_subscriptions_activation" then perform_subscriptions_activation
    when "refresh_invoice" then refresh_invoice(golden_target_invoice_record(ctx, step))
    when "finalize_invoice" then finalize_invoice(golden_target_invoice_record(ctx, step))
    when "void_invoice" then void_invoice(golden_target_invoice_record(ctx, step))
    else raise ArgumentError, "golden row: unknown step #{step["do"].inspect}"
    end
  end

  def golden_create_subscription(step, ctx, row)
    subscription = (row.dig("setup", "subscription") || {}).merge(step["params"] || {})
    params = {
      external_customer_id: ctx[:customer][:external_id],
      external_id: subscription["external_id"] || "golden_subscription",
      plan_code: subscription["plan_code"] || ctx[:plan][:code],
      billing_time: subscription["billing_time"] || "calendar"
    }
    params[:subscription_at] = subscription["subscription_at"] if subscription["subscription_at"]
    params[:plan_overrides] = golden_plan_overrides(subscription["plan_overrides"], ctx) if subscription["plan_overrides"]
    params[:ending_at] = subscription["ending_at"] if subscription["ending_at"]
    # Only settable at creation: ActivationRules::ApplyService refuses a subscription that is not
    # `pending`, and the only pending window is inside CreateService.
    params[:activation_rules] = subscription["activation_rules"].map(&:symbolize_keys) if subscription["activation_rules"]

    failing = row.dig("expect", "error")
    if failing && failing["stage"] == "subscription"
      response = create_subscription(params, raise_on_error: false)
      assert_golden_error(failing, response)
    end

    ctx[:subscription] = create_subscription(params, as: :model)
    golden_apply_termination_policy(subscription, ctx)
  end

  # A PUT rather than two more entries in the create payload: neither key is settable at creation —
  # CreateService ignores both even when handed them, and they appear only in `update_params`.
  # `on_termination_credit_note` is refused outright on an arrears plan.
  TERMINATION_POLICY_KEYS = %w[on_termination_credit_note on_termination_invoice].freeze

  def golden_apply_termination_policy(subscription, ctx)
    policy = TERMINATION_POLICY_KEYS.each_with_object({}) do |key, out|
      out[key.to_sym] = subscription[key] if subscription.key?(key)
    end
    return if policy.empty?

    update_subscription(ctx[:subscription], policy)
    ctx[:subscription].reload
  end

  # `plan_overrides.fixed_charges` and `.charges` are indexed by the record's UUID, which a YAML row
  # cannot know, so rows name the fixed charge by code and this resolves it against the plan.
  def golden_plan_overrides(overrides, ctx)
    resolved = overrides.deep_symbolize_keys
    return resolved unless resolved[:fixed_charges] && ctx[:plan]

    plan = Plan.find(ctx[:plan][:lago_id])
    resolved[:fixed_charges] = resolved[:fixed_charges].map do |entry|
      entry = entry.dup
      code = entry.delete(:add_on_code) || entry.delete(:code)
      next entry unless code

      fixed_charge = plan.fixed_charges.find { |candidate| candidate.code == code }
      unless fixed_charge
        raise ArgumentError,
          "golden row: plan_overrides names fixed charge #{code.inspect}, which the plan does not " \
          "have; it declares #{plan.fixed_charges.map(&:code).inspect}"
      end

      entry.merge(id: fixed_charge.id)
    end

    resolved
  end

  def golden_ingest_events(step, ctx)
    (step["events"] || []).each do |event|
      event.fetch("count", 1).times do
        payload = {
          code: event["code"],
          external_subscription_id: ctx[:subscription].external_id,
          timestamp: (event["timestamp"] ? golden_time(event["timestamp"]) : Time.current).to_f,
          properties: event["properties"] || {}
        }
        # Top-level, not a property: the dynamic charge model reads its amount from here.
        payload[:precise_total_amount_cents] = event["precise_total_amount_cents"] if event.key?("precise_total_amount_cents")
        create_event(payload)
      end
    end
  end

  # regroup_paid_fees means literally *paid* fees: AdvanceChargesService only picks up fees with
  # payment_status succeeded, while CreatePayInAdvanceService creates them pending.
  def golden_pay_fees(ctx)
    response = api_call do
      get_with_token(organization, "/api/v1/fees", {external_subscription_id: ctx[:subscription].external_id, per_page: 100})
    end

    response.fetch(:fees)
      .select { |fee| fee[:lago_invoice_id].nil? && fee.dig(:item, :type) == "charge" }
      .each { |fee| update_fee(fee[:lago_id], {payment_status: "succeeded"}) }
  end

  # A paid top-up creates its wallet transaction pending, so its credits are unspendable until the
  # top-up invoice is settled.
  def golden_pay_invoice(step, ctx)
    invoices = golden_fetch_invoices(ctx)
    scoped = step["invoice_type"] ? invoices.select { |i| i[:invoice_type] == step["invoice_type"] } : invoices
    target = scoped.last
    raise "golden row: no invoice to pay for type #{step["invoice_type"].inspect}" unless target

    create_payment(golden_customer_record(ctx), Invoice.find(target[:lago_id]), target[:total_amount_cents])
    perform_wallet_refresh
  end

  # The only door to `fee_type: :add_on`: no subscription invoice, draft or preview can carry one.
  # `units` and `tax_codes` apply to every fee in the call rather than per add-on, so two add-ons that
  # must differ do so through their own amount_cents or add-on-level taxes. `tax_codes: []` is not a
  # distinct assertion — OneOffService gates on `tax_codes.present?`.
  def golden_create_one_off_invoice(step, ctx)
    spec = step.fetch("one_off")
    codes = spec.fetch("add_ons")
    missing = codes - ctx[:add_ons].keys
    if missing.any?
      raise ArgumentError,
        "golden row: create_one_off_invoice names add-on(s) #{missing.inspect}, which the row does " \
        "not declare; declared add-ons are #{ctx[:add_ons].keys.inspect}"
    end

    params = {currency: ctx[:customer][:currency] || "EUR"}
    params[:units] = spec["units"] if spec.key?("units")
    params[:taxes] = spec["tax_codes"] if spec.key?("tax_codes")

    add_ons = codes.map { |code| AddOn.find(ctx[:add_ons][code][:lago_id]) }
    create_one_off_invoice(golden_customer_record(ctx), add_ons, **params)
  end

  # Items are declared by fee_type and resolved to fee ids here. Mind the API's asymmetry: item
  # amounts are pre-tax, while the credit/refund/offset amounts are tax-inclusive totals.
  def golden_create_credit_note(step, ctx)
    spec = step.fetch("credit_note")
    invoices = golden_fetch_invoices(ctx)
    scoped = spec["invoice_type"] ? invoices.select { |i| i[:invoice_type] == spec["invoice_type"] } : invoices
    target = scoped.last or raise "golden row: no invoice to credit"
    fees = golden_fetch_invoice(target[:lago_id]).fetch(:fees)

    items = spec.fetch("items").map do |item|
      fee = fees.find { |candidate| candidate.dig(:item, :type) == item["fee_type"] }
      unless fee
        raise "golden row: invoice has no #{item["fee_type"]} fee to credit; " \
              "fee types present: #{fees.map { |f| f.dig(:item, :type) }.inspect}"
      end
      {fee_id: fee[:lago_id], amount_cents: item["amount_cents"]}
    end

    params = {invoice_id: target[:lago_id], items: items}
    params[:reason] = spec["reason"] || "other"
    %w[credit_amount_cents refund_amount_cents offset_amount_cents].each do |key|
      params[key.to_sym] = spec[key] if spec.key?(key)
    end

    ctx[:credit_note] = create_credit_note(params).fetch(:credit_note)
  end

  # Current usage describes the period in progress and has to be captured while it is still open:
  # after perform_billing the subscription has rolled into a fresh, empty period. Without a
  # fetch_current_usage step, `expect.usage` reads live usage at assertion time instead.
  def golden_snapshot_usage(ctx, row)
    failing = row.dig("expect", "error")

    if failing && failing["stage"] == "usage"
      response = fetch_current_usage(
        customer: golden_customer_record(ctx),
        subscription: ctx[:subscription],
        raise_on_error: false
      )
      assert_golden_error(failing, response)
    end

    ctx[:usage] = fetch_current_usage(customer: golden_customer_record(ctx), subscription: ctx[:subscription])
      .fetch(:customer_usage)
  end

  # Updates a charge on the PARENT plan. With cascade_updates the change is pushed down to child
  # plans created by subscription overrides; without it the children keep what they were given.
  def golden_update_plan_charge(step, ctx)
    spec = step.fetch("charge")
    # The endpoint is a full replacement rather than a patch, so charge_model must be resent even
    # when it is unchanged — omitting it fails with charge_model/value_is_mandatory.
    params = {charge_model: spec.fetch("charge_model")}
    params[:properties] = spec["properties"] if spec.key?("properties")
    params[:min_amount_cents] = spec["min_amount_cents"] if spec.key?("min_amount_cents")
    params[:cascade_updates] = spec["cascade_updates"] if spec.key?("cascade_updates")
    # `filters` is a REPLACEMENT array: entries are resolved against the charge's existing filters by
    # their `values` rather than by id, and omitted ones are discarded. So `filters: []` is the
    # delete, and the key is forwarded on `key?` rather than on presence.
    params[:filters] = spec["filters"] if spec.key?("filters")

    # A charge created inline on a plan takes its billable metric's code as its own.
    update_plan_charge(Plan.find(ctx[:plan][:lago_id]), spec.fetch("billable_metric_code"), params)
  end

  # Moves a fixed charge's units on the PARENT plan, emitting a fresh FixedChargeEvent.
  # `apply_units_immediately` decides which period that event lands in — `Time.current` when true,
  # `fixed_charges_period_to_datetime + 1.second` when false, i.e. beyond the current aggregation — so
  # the same body bills two different amounts and `false` must survive as a value.
  # `properties` is mandatory alongside `charge_model`: the endpoint replaces it, and an omitted one
  # falls back to the charge model's default properties, repricing the charge to zero.
  def golden_update_plan_fixed_charge(step, ctx)
    spec = step.fetch("fixed_charge")
    params = {
      charge_model: spec.fetch("charge_model"),
      units: spec.fetch("units"),
      properties: spec.fetch("properties")
    }
    params[:apply_units_immediately] = spec["apply_units_immediately"] if spec.key?("apply_units_immediately")
    params[:tax_codes] = spec["tax_codes"] if spec.key?("tax_codes")
    params[:cascade_updates] = spec["cascade_updates"] if spec.key?("cascade_updates")

    update_plan_fixed_charge(Plan.find(ctx[:plan][:lago_id]), golden_fixed_charge_code(spec), params)
  end

  # `plan_overrides` does not edit the plan: it creates an OVERRIDE plan with fresh charge records and
  # repoints the subscription at them, leaving everything accumulated against the old charge ids
  # reachable only to services that follow the override.
  def golden_update_subscription(step, ctx)
    params = (step["params"] || {}).deep_symbolize_keys
    update_subscription(ctx[:subscription], params)
    ctx[:subscription].reload
  end

  # A units-only body writes a Subscription::FixedChargeUnitsOverride and later plan-level updates
  # then skip this subscription; sending anything more switches the service to the plan-clone path.
  # Premium-gated, so rows using it need `premium: true`.
  def golden_update_subscription_fixed_charge(step, ctx)
    spec = step.fetch("fixed_charge")
    params = {units: spec.fetch("units")}
    params[:apply_units_immediately] = spec["apply_units_immediately"] if spec.key?("apply_units_immediately")
    params[:properties] = spec["properties"] if spec.key?("properties")
    params[:invoice_display_name] = spec["invoice_display_name"] if spec.key?("invoice_display_name")
    params[:tax_codes] = spec["tax_codes"] if spec.key?("tax_codes")

    update_subscription_fixed_charge(ctx[:subscription], golden_fixed_charge_code(spec), params)
  end

  def golden_fixed_charge_code(spec)
    spec["code"] || spec.fetch("add_on_code")
  end

  def golden_customer_record(ctx)
    Customer.find_by!(external_id: ctx[:customer][:external_id], organization:)
  end

  # The invoice a row wants is often not the newest — a mid-period override issues its own — so rows
  # point at another with the same `select` they use in expectations.
  def golden_target_invoice_record(ctx, step = nil)
    selector = (step && step["select"]) ? step["select"] : "last"

    Invoice.find(golden_select_invoice(golden_fetch_invoices(ctx), selector)[:lago_id])
  end

  # ---------------------------------------------------------------- assertions

  def assert_golden_expectations(row, ctx)
    expectation = row["expect"]
    golden_assert_error_fired(expectation)

    if expectation.key?("invoices") || expectation.key?("invoice")
      invoices = golden_fetch_invoices(ctx)
      expect(invoices.size).to eq(expectation["invoices"]) if expectation.key?("invoices")
      # A single hash or a list: money moving BETWEEN invoices is only pinned down by asserting both
      # sides, so each named invoice carries its own `select`.
      Array.wrap(expectation["invoice"]).each { |expected| assert_golden_invoice(expected, invoices) }
    end

    assert_golden_usage(expectation["usage"], ctx) if expectation["usage"]
    assert_golden_resource(expectation["resource"], ctx) if expectation["resource"]
    assert_golden_credit_note(expectation["credit_note"], ctx) if expectation["credit_note"]
    # A single hash or a list. The multi-wallet-priority axis is DEFINED by what the other wallet
    # kept, so asserting one balance and inferring the other arithmetically is not the same claim.
    Array.wrap(expectation["wallet"]).each { |expected| assert_golden_wallet(expected, ctx) }
    assert_golden_preview(expectation["preview"], ctx) if expectation["preview"]
    assert_golden_lifetime_usage(expectation["lifetime_usage"], ctx) if expectation["lifetime_usage"]
  end

  def golden_assert_error_fired(expectation)
    return unless expectation.key?("error")

    raise ArgumentError,
      "golden row: expect.error at stage #{expectation.dig("error", "stage").inspect} never fired — " \
      "the row reached its assertions without ever performing the call that must be rejected, so it " \
      "asserts nothing. Add the step that triggers it."
  end

  # PUT /plans/:code replaces the plan wholesale, charges included, so the existing charges are resent
  # by id unless the row names its own. Unlike Charges::UpdateService, Plans::UpdateService flags the
  # customer's draft invoices for refresh.
  def golden_update_plan(step, ctx)
    params = (step["params"] || {}).symbolize_keys
    plan = Plan.find(ctx[:plan][:lago_id])

    params[:charges] = if params.key?(:charges)
      params[:charges].map { |charge| golden_update_plan_charge_entry(charge, ctx) }
    else
      plan.charges.map do |charge|
        {
          id: charge.id,
          billable_metric_id: charge.billable_metric_id,
          charge_model: charge.charge_model,
          properties: charge.properties
        }
      end
    end

    update_plan(plan, params)
  end

  # The API permits only `billable_metric_id`, a UUID a YAML row cannot know, so rows name the metric
  # by code. An entry with no `id` creates a charge while the omitted ones are discarded, which is how
  # a row replaces a charge record — new `charge_id`, same plan, subscription and metric.
  def golden_update_plan_charge_entry(charge, ctx)
    entry = charge.symbolize_keys
    code = entry.delete(:billable_metric_code) or return entry

    metric = ctx[:metrics][code]
    unless metric
      raise ArgumentError,
        "golden row: update_plan names metric #{code.inspect}, which the row does not declare; " \
        "declared metrics are #{ctx[:metrics].keys.inspect}"
    end

    entry.merge(billable_metric_id: metric[:lago_id])
  end

  # Not interchangeable with deleting the charge (`update_plan` with `charges: []`):
  # BillableMetrics::DestroyService also flags the customer's open drafts ready_to_be_refreshed, and
  # Charges::DestroyService does not.
  def golden_delete_metric(step, ctx)
    code = step["code"] || ctx[:metrics].keys.first
    unless ctx[:metrics].key?(code)
      raise ArgumentError,
        "golden row: delete_metric names metric #{code.inspect}, which the row does not declare; " \
        "declared metrics are #{ctx[:metrics].keys.inspect}"
    end

    delete_metric(code)
    ctx[:metrics].delete(code)
  end

  def golden_update_tax(step, ctx)
    code = step["code"] || ctx[:taxes].first
    api_call { put_with_token(organization, "/api/v1/taxes/#{code}", {tax: (step["params"] || {}).symbolize_keys}) }
  end

  # Editing a coupon does not touch coupons already applied: AppliedCoupon copies amount, percentage
  # and frequency at application time.
  def golden_update_coupon(step, ctx)
    code = step["code"] || ctx[:coupons].first
    api_call { put_with_token(organization, "/api/v1/coupons/#{code}", {coupon: (step["params"] || {}).symbolize_keys}) }
  end

  # Granted credits land on the wallet immediately; paid credits raise a `credit` invoice and are
  # unusable until it is settled.
  # `code` names WHICH wallet, and it matters beyond convenience: `find_by!` with no ORDER BY picks an
  # arbitrary row, so a two-wallet row topping up "the wallet" was funding one of them at random. It is
  # also the only route to two wallets both holding SETTLED purchased credit — a top-up per wallet at
  # its own timeline instant gives each `credit` invoice a distinct created_at, which `pay_invoice`
  # (newest-first) can then settle one at a time.
  def golden_top_up_wallet(step, ctx)
    params = (step["params"] || {}).symbolize_keys
    customer = Customer.find_by!(external_id: ctx[:customer][:external_id])
    wallets = customer.wallets.order(:created_at)
    wallet = if step["code"]
      wallets.find_by(code: step["code"]) ||
        raise("golden row: top_up_wallet names wallet #{step["code"].inspect}; customer has " \
              "#{wallets.pluck(:code).inspect}")
    else
      wallets.first || raise("golden row: top_up_wallet but the customer has no wallet")
    end

    create_wallet_transaction(params.merge(wallet_id: wallet.id))
  end

  def golden_update_customer(step, ctx)
    params = golden_customer_params(step["params"] || {})
    create_or_update_customer(params.merge(external_id: ctx[:customer][:external_id]))
  end

  # The endpoint names none of its four contexts — they are inferred from the params. No
  # `subscriptions.external_ids` means a PROPOSAL built from a top-level `plan_code`; external_ids
  # alone PROJECTS the existing subscription; `terminated_at` previews a termination and a nested
  # `plan_code` a plan change. Projection is the default because add_charge_fees returns early unless
  # the subscription is persisted, so a proposal always reports zero usage.
  def golden_preview_invoice(step, ctx)
    params = (step["params"] || {}).deep_symbolize_keys

    unless params.key?(:plan_code)
      params[:subscriptions] = {external_ids: [ctx[:subscription].external_id]}
        .merge(params[:subscriptions] || {})
    end

    ctx[:preview] = api_call do
      post_with_token(organization, "/api/v1/invoices/preview",
        {customer: {external_id: ctx[:customer][:external_id]}}.merge(params))
    end.fetch(:invoice)
  end

  # An invoice shows how much prepaid credit was applied but not which wallet supplied it or what its
  # balance became, so ordering, limitation and ongoing balance can only be asserted here.
  def assert_golden_wallet(expected, ctx)
    expected = expected.dup
    code = expected.delete("code")
    wallets = api_call do
      get_with_token(organization, "/api/v1/wallets", {external_customer_id: ctx[:customer][:external_id], per_page: 100})
    end.fetch(:wallets)

    wallet = code ? wallets.find { |candidate| candidate[:code] == code } : wallets.first
    unless wallet
      raise "golden row: no wallet #{code ? code.inspect : "at all"}; customer has #{wallets.map { |w| w[:code] }.inspect}"
    end

    GoldenComparison.assert_fields!("wallet#{"[#{code}]" if code}", expected, wallet)
  end

  # Cumulative usage across the subscription's whole life — what progressive-billing thresholds are
  # measured against, not per-period current usage. `select` carries the subscription status the read
  # is scoped to: the controller resolves external_id with `status: params[:status] || :active`, so
  # the default read answers 404 once the subscription is terminated.
  def assert_golden_lifetime_usage(expected, ctx)
    expected = expected.dup
    select = (expected.delete("select") || {}).symbolize_keys

    if expected.empty?
      raise ArgumentError,
        "golden row: expect.lifetime_usage carries only a `select` and asserts nothing — name at " \
        "least one field of the payload."
    end

    usage = api_call do
      get_with_token(
        organization,
        "/api/v1/subscriptions/#{ctx[:subscription].external_id}/lifetime_usage",
        select
      )
    end.fetch(:lifetime_usage)

    GoldenComparison.assert_fields!("lifetime_usage", expected, usage)
  end

  def assert_golden_preview(expected, ctx)
    preview = ctx[:preview] or raise "golden row: expects a preview but no preview_invoice step ran"
    assert_golden_invoice_payload(expected, preview, subject: "preview")
  end

  def assert_golden_credit_note(expected, ctx)
    expected = expected.dup
    items_count = expected.delete("items_count")
    credit_note = golden_target_credit_note(expected.delete("select"), ctx)

    GoldenComparison.assert_fields!("credit_note", expected, credit_note)

    return unless items_count
    return if credit_note[:items].size == items_count
    raise RSpec::Expectations::ExpectationNotMetError,
      GoldenComparison.message("credit_note", "items_count", items_count, credit_note[:items].size)
  end

  # No selector means the credit note the row's own create_credit_note step made. A selector reaches
  # the ones Lago produced by itself (progressive billing, termination), which ctx never holds.
  #
  # Either way the note is RE-READ here rather than asserted from ctx. `ctx[:credit_note]` is the
  # payload as it stood at CREATION, so a row asserting `balance_amount_cents` on it could not see a
  # balance the rest of the timeline consumed — the obvious way to write such a row passed while
  # asserting a number that no longer existed.
  def golden_target_credit_note(select, ctx)
    if select.nil?
      created = ctx[:credit_note] || raise("golden row: expects a credit_note but none was created")
      return golden_read_credit_note(created[:lago_id])
    end

    listed = api_call do
      get_with_token(
        organization,
        "/api/v1/credit_notes",
        {external_customer_id: ctx[:customer][:external_id], per_page: 100}
      )
    end.fetch(:credit_notes).sort_by { |note| note[:created_at] }

    golden_read_credit_note(golden_select_record(listed, select, kind: "credit_note")[:lago_id])
  end

  # Through `show` for the same reason invoices are: the index serializer omits items.
  def golden_read_credit_note(lago_id)
    api_call { get_with_token(organization, "/api/v1/credit_notes/#{lago_id}") }.fetch(:credit_note)
  end

  def assert_golden_resource(expected, ctx)
    actual = golden_resource(expected, ctx)

    GoldenComparison.assert_fields!(expected["kind"], expected.fetch("fields"), actual)
  end

  def golden_resource(expected, ctx)
    case expected["kind"]
    when "metric"
      code = expected["code"] || ctx[:metrics].keys.first
      api_call { get_with_token(organization, "/api/v1/billable_metrics/#{code}") }.fetch(:billable_metric)
    when "plan"
      api_call { get_with_token(organization, "/api/v1/plans/#{expected["code"] || ctx[:plan][:code]}") }.fetch(:plan)
    when "customer"
      api_call { get_with_token(organization, "/api/v1/customers/#{expected["code"] || ctx[:customer][:external_id]}") }.fetch(:customer)
    when "charge"
      plan = api_call { get_with_token(organization, "/api/v1/plans/#{ctx[:plan][:code]}") }.fetch(:plan)
      charges = plan.fetch(:charges)
      expected["code"] ? charges.find { |charge| charge[:billable_metric_code] == expected["code"] } : charges.first
    else
      raise ArgumentError, "golden row: unknown resource kind #{expected["kind"].inspect}"
    end
  end

  # The index serializer omits fees, so this counts and selects; the chosen invoice is then re-read
  # through show.
  def golden_fetch_invoices(ctx)
    response = api_call do
      get_with_token(organization, "/api/v1/invoices", {external_customer_id: ctx[:customer][:external_id], per_page: 100})
    end
    response.fetch(:invoices).sort_by { |invoice| invoice[:created_at] }
  end

  def golden_fetch_invoice(lago_id)
    api_call { get_with_token(organization, "/api/v1/invoices/#{lago_id}") }.fetch(:invoice)
  end

  RECORD_IDENTITY_FIELDS = {
    "invoice" => %i[invoice_type status],
    "credit_note" => %i[credit_status reason]
  }.freeze

  # One selector idiom for every list a row can point into: "first", "last", or a hash of field values
  # with an optional `index` into what those fields matched.
  def golden_select_record(records, selector, kind:)
    selector = "last" if selector.nil?

    if selector.is_a?(Hash)
      filters = selector.except("index")
      scoped = records.select do |record|
        filters.all? { |field, value| record[field.to_sym].to_s == value.to_s }
      end

      return scoped[selector["index"] || -1] || raise_golden_no_record(records, selector, kind)
    end

    record = (selector == "first") ? records.first : records.last
    record || raise_golden_no_record(records, selector, kind)
  end

  def golden_select_invoice(invoices, selector)
    golden_select_record(invoices, selector, kind: "invoice")
  end

  def raise_golden_no_record(records, selector, kind)
    identity = RECORD_IDENTITY_FIELDS.fetch(kind)
    raise "golden row: no #{kind} matched selector #{selector.inspect}; customer has " \
          "#{records.size} #{kind}(s): #{records.map { |record| record.values_at(*identity) }.inspect}"
  end

  def assert_golden_invoice(expected, invoices)
    expected = expected.dup
    select = expected.delete("select")
    selected = golden_select_invoice(invoices, select)
    assert_golden_invoice_payload(
      expected,
      golden_fetch_invoice(selected[:lago_id]),
      subject: golden_invoice_subject(select)
    )
  end

  def golden_invoice_subject(select)
    return "invoice" if select.blank?
    return "invoice[#{select}]" unless select.is_a?(Hash)

    "invoice[#{select.map { |field, value| "#{field}=#{value}" }.join(",")}]"
  end

  def assert_golden_invoice_payload(expected, invoice, subject: "invoice")
    expected = expected.except("select")
    fees = expected["fees"]
    fees_count = expected["fees_count"]

    GoldenComparison.assert_fields!(subject, expected.except("fees", "fees_count"), invoice)

    actual_fees = invoice[:fees] || []
    if fees_count && actual_fees.size != fees_count
      raise RSpec::Expectations::ExpectationNotMetError,
        GoldenComparison.message(subject, "fees_count", fees_count, actual_fees.size)
    end
    assert_golden_fees(fees, actual_fees) if fees
  end

  def assert_golden_fees(expected_fees, actual_fees)
    expect(actual_fees.size).to eq(expected_fees.size),
      "expected #{expected_fees.size} fee(s), got #{actual_fees.size}:\n#{golden_fees_dump(actual_fees)}"

    remaining = actual_fees.dup
    expected_fees.each_with_index do |expected, index|
      match = remaining.find { |fee| golden_fee_matches?(expected, fee, FEE_MATCH_KEYS) }
      unless match
        raise RSpec::Expectations::ExpectationNotMetError,
          "expected fee ##{index + 1} #{expected.inspect} matched none of the remaining fees:\n#{golden_fees_dump(remaining)}"
      end
      remaining.delete(match)
      GoldenComparison.assert_fields!("fee ##{index + 1}", expected, match)
    end
  end

  def golden_fee_matches?(expected, fee, keys)
    GoldenComparison.matches?(expected, fee, keys)
  end

  def assert_golden_usage(expected, ctx)
    usage = ctx[:usage] ||
      fetch_current_usage(customer: golden_customer_record(ctx), subscription: ctx[:subscription]).fetch(:customer_usage)
    expected = expected.dup
    charges = expected.delete("charges_usage")

    GoldenComparison.assert_fields!("usage", expected, usage)

    (charges || []).each do |expected_charge|
      code = expected_charge["billable_metric_code"]
      actual = usage[:charges_usage].find { |c| c.dig(:billable_metric, :code) == code }
      raise "golden row: no charge usage for metric #{code.inspect}" unless actual

      GoldenComparison.assert_fields!("usage[#{code}]", expected_charge.except("billable_metric_code"), actual)
    end
  end

  def assert_golden_error(expected, response)
    expect(response_status_for_golden).to eq(expected["status"]),
      "expected HTTP #{expected["status"]} on #{expected["stage"]}, got #{response_status_for_golden}: #{response.inspect}"

    details = response[:error_details] || {}
    codes = details.values.flatten.map(&:to_s)
    codes << response[:code].to_s if response[:code]

    expect(codes).to include(expected["code"]),
      "expected error code #{expected["code"].inspect} on #{expected["stage"]}, got #{details.inspect}"

    if expected["field"]
      expect(details.keys.map(&:to_s)).to include(expected["field"]),
        "expected error on field #{expected["field"].inspect}, got fields #{details.keys.inspect}"
    end

    # Stops the row rather than letting it walk into a timeline built on a half-created context.
    # Deliberately not in an `ensure`: a `throw` there discards the exception in flight, which
    # swallows the comparisons above whenever aggregate_failures is off.
    throw :golden_row_done
  end

  def response_status_for_golden
    response.status
  end

  def golden_fees_dump(fees)
    fees.map do |fee|
      "  - fee_type=#{fee.dig(:item, :type)} item_code=#{fee.dig(:item, :code)} units=#{fee[:units]} " \
        "amount_cents=#{fee[:amount_cents]} taxes_amount_cents=#{fee[:taxes_amount_cents]} " \
        "period=#{fee[:from_date]}..#{fee[:to_date]}"
    end.join("\n")
  end
end
