# frozen_string_literal: true

# Which cells of the golden matrix are legal, derived rather than declared.
#
# Two halves:
#
#   * DOMAINS come straight from the model constants, so when Lago gains a charge model, an
#     aggregation or an interval, the coverage denominator grows by itself and the new cells show up
#     as unclaimed in the next ledger run. Nothing here lists enum values by hand.
#
#   * CONSTRAINTS mirror the private validators on Charge and FixedCharge. These are the one place
#     the suite restates implementation, so each carries its source citation AND is verified against
#     the real validation by spec/scenarios/golden/legality_spec.rb — if a rule changes under us the
#     agreement spec fails and names the cell, instead of the matrix quietly measuring the wrong
#     denominator.
module GoldenLegality
  module_function

  def domains
    {
      charge_models: Charge::CHARGE_MODELS.map(&:to_sym),
      aggregations: BillableMetric::AGGREGATION_TYPES.keys.map(&:to_sym),
      intervals: Plan::INTERVALS.map(&:to_sym),
      billing_times: Subscription::BILLING_TIME.map(&:to_sym),
      fee_types: Fee::FEE_TYPES.map(&:to_sym),
      invoice_types: Invoice::INVOICE_TYPES.map(&:to_sym),
      on_termination_credit_notes: Subscription::ON_TERMINATION_CREDIT_NOTES.keys.map(&:to_sym),
      on_termination_invoices: Subscription::ON_TERMINATION_INVOICES.keys.map(&:to_sym),
      regroup_paid_fees_options: Charge::REGROUPING_PAID_FEES_OPTIONS.map(&:to_sym),
      fixed_charge_models: FixedCharge::CHARGE_MODELS.keys.map(&:to_sym),
      wallet_transaction_sources: WalletTransaction::SOURCES.map(&:to_sym),
      wallet_transaction_statuses: WalletTransaction::TRANSACTION_STATUSES.map(&:to_sym),
      coupon_types: Coupon::COUPON_TYPES.map(&:to_sym),
      coupon_frequencies: Coupon::FREQUENCIES.map(&:to_sym),
      credit_note_types: CreditNote::TYPES.map(&:to_sym),
      credit_note_reasons: CreditNote::REASON.map(&:to_sym)
    }
  end

  # Domains that are computed rather than read off a model constant.
  def derived_domains
    {
      billing_features: billing_features,
      reducer_stacks: reducer_stacks,
      duplicable_features: duplicable_features,
      churns: churns,
      carried_states: carried_states,
      surface_subject_blocks: surface_subject_blocks,
      surfaces: surfaces
    }
  end

  def domain(name)
    all = domains.merge(derived_domains)
    all.fetch(name.to_sym) do
      raise ArgumentError, "unknown golden domain #{name.inspect}; known: #{all.keys.sort.inspect}"
    end
  end

  # Aggregations that may carry recurring: true — BillableMetric#validate_recurring
  # (app/models/billable_metric.rb:108-113) rejects count_agg, max_agg and latest_agg.
  def recurring_capable
    domain(:aggregations) - %i[count_agg max_agg latest_agg]
  end

  # BillableMetric::AGGREGATION_TYPES_PAYABLE_IN_ADVANCE (app/models/billable_metric.rb:42).
  def payable_in_advance
    BillableMetric::AGGREGATION_TYPES_PAYABLE_IN_ADVANCE.map(&:to_sym)
  end

  # graduated_percentage is legal but licence-gated — Charge#charge_model_allowance
  # (app/models/charge.rb:184-188). Rows covering these cells must set `premium: true`.
  def premium_charge_model?(charge_model)
    charge_model.to_sym == :graduated_percentage
  end

  # Gated one level up and by an org flag rather than by License.premium?: the METRIC is refused with
  # 403 feature_unavailable unless organization.custom_aggregation is set (BillableMetrics::CreateService:20).
  def org_gated_aggregation?(aggregation)
    aggregation.to_sym == :custom_agg
  end

  # Values no REST caller can reach, which the ledger subtracts from the denominator and reports.
  # Each entry carries its reason and should be deleted the day the API grows the surface.
  API_UNREACHABLE_AXIS_VALUES = {
    # `custom_aggregator` is absent from BillableMetricsController#input_params, so a REST POST cannot
    # create a custom_agg metric at all, and with it the only legal cell of the `custom` charge model.
    aggregation: %w[custom_agg],

    # Fee adjustment exists only as GraphQL mutations (app/graphql/mutations/adjusted_fees/), with
    # no Api::V1 counterpart.
    operation: %w[adjust-fee-units adjust-fee-amount],

    # Daily usages have no REST controller and no route whatsoever — only the internal
    # `analytics/usage` data-api endpoint, which is a different thing with a different shape.
    surface: %w[daily-usage]
  }.freeze

  # The two rungs of the Fees::ApplyTaxesService ladder (apply_taxes_service.rb:64-78) that only a fee
  # on a ONE-OFF invoice can stand on: fees/one_off_service.rb is the only call site passing
  # `tax_codes`, and the only place `fee_type: :add_on` is assigned.
  ONE_OFF_ONLY_TAX_LEVELS = %w[add-on explicit-codes].freeze

  # An intersection that is unreachable although each of its values is reachable alone, which is why
  # it cannot live in API_UNREACHABLE_AXIS_VALUES. No Credits::AppliedCouponsService call site is on
  # the one-off path, so an applied coupon is never consulted while a one-off invoice is built and
  # there is no coupon-before-tax ordering to observe. Guarded on the cell having a coupon axis, so a
  # couponless block using `tax_level` keeps all of its values.
  def coupon_with_one_off_only_tax_level?(cell)
    return false unless ONE_OFF_ONLY_TAX_LEVELS.include?(cell[:tax_level].to_s)

    cell.key?(:coupon_type) || cell.key?(:coupon_frequency)
  end

  # An add-on fee exists on one-off invoices and nowhere else. Preview cannot carry one —
  # InvoicesController#preview_params permits no `fees` key, and nothing under invoices/preview/
  # mentions an add-on — and a one-off is never a draft, so RefreshDraftService refuses it outright
  # (`unless invoice.subscription?`). Keyed on the pair, since each value is reachable on its own.
  ADD_ON_FEE_UNREACHABLE_SURFACES = %w[preview regenerated draft].freeze

  def add_on_fee_on_unreachable_surface?(cell)
    return false unless cell[:feature].to_s == "add_on"

    ADD_ON_FEE_UNREACHABLE_SURFACES.include?(cell[:observed_via].to_s)
  end

  def api_reachable?(cell)
    return false if coupon_with_one_off_only_tax_level?(cell)
    return false if add_on_fee_on_unreachable_surface?(cell)

    API_UNREACHABLE_AXIS_VALUES.none? do |axis, unreachable|
      value = cell[axis]
      value && unreachable.include?(value.to_s)
    end
  end

  # The features that can appear on one invoice, in the order Invoices::CalculateFeesService applies
  # them (calculate_fees_service.rb:42-63): producers add to fees_amount_cents, reducers subtract at a
  # fixed stage, so which of them runs first decides the amount. Declared rather than derived — no
  # constant enumerates the pipeline — and checked against the source by legality_spec.rb.
  BILLING_FEATURE_PRODUCERS = %w[
    subscription_fee charge fixed_charge advance_charge commitment_true_up min_amount_true_up
  ].freeze

  BILLING_FEATURE_REDUCERS = %w[
    progressive_billing coupon tax credit_note prepaid_credit
  ].freeze

  def billing_features
    (BILLING_FEATURE_PRODUCERS + BILLING_FEATURE_REDUCERS).sort
  end

  def reducer?(feature)
    BILLING_FEATURE_REDUCERS.include?(feature.to_s)
  end

  # Below this a combination is a PAIR and belongs to B15 ("which of the two runs first"). From three
  # up the question is whether a stage is still handed the right base, which no pair row can observe.
  MINIMUM_STACK = 3

  # Every way MINIMUM_STACK or more reducers can land on one invoice, named in pipeline order.
  def reducer_stacks
    (MINIMUM_STACK..BILLING_FEATURE_REDUCERS.size).flat_map do |size|
      BILLING_FEATURE_REDUCERS.combination(size).map { |stack| stack.join("+") }
    end
  end

  # Features the API accepts a collection of. Two instances raise a question one cannot: whether they
  # simply add, and if they compete for the same money, which is consumed first. legality_spec.rb
  # builds two of each and checks Lago permits it.
  DUPLICABLE_FEATURES = %w[
    coupon credit_note prepaid_credit tax charge fixed_charge add_on subscription_fee
  ].freeze

  # Those drawing on a finite pool, so two can together exceed it and the allocation order decides who
  # gets what. Everything else simply adds and cannot be `capped`.
  CAPPABLE_FEATURES = %w[coupon credit_note prepaid_credit].freeze

  def duplicable_features
    DUPLICABLE_FEATURES
  end

  def cappable?(feature)
    CAPPABLE_FEATURES.include?(feature.to_s)
  end

  # ------------------------------------------------------------------- surfaces
  #
  # A draft, a regenerated draft and a preview are three different computations of the same period:
  # coupons, credit notes and prepaid credit are all gated on `not_in_finalizing_process?`, so a draft
  # withholds every one of them. A block belongs here when its behaviour can differ across the three,
  # i.e. it involves a gated reducer or is recomputed on refresh.
  SURFACE_SUBJECT_BLOCKS = %w[B5 B6 B8 B9 B10 B12 B15 B19].freeze

  # B21's axis: the three surfaces that can DIFFER from a finalized invoice. Widening it to the whole
  # vocabulary would take the block from 24 cells to 56, most of them cases where draft and final
  # provably agree.
  SURFACES = %w[draft regenerated preview].freeze

  # The vocabulary every surface-ish axis must draw from. Used by the lint, not as anyone's domain.
  SURFACE_VOCABULARY = %w[invoice draft regenerated preview current-usage daily-usage
    lifetime-usage].freeze

  # B7's `surface` axis carries one extra value that is NOT a surface: `usage-equals-invoice` asserts
  # that two surfaces AGREE, which is an invariant rather than a place to look. Exempted by name.
  NON_SURFACE_AXIS_VALUES = %w[usage-equals-invoice].freeze

  def surface_subject_blocks
    SURFACE_SUBJECT_BLOCKS
  end

  def surfaces
    SURFACES
  end

  # ---------------------------------------------------------------- identity churn
  #
  # Lago finds carried state again by joining on record ids, so a configuration change that rewrites
  # one of those ids can lose the state silently — the lookup returns nothing rather than failing.
  # Both tables below are verified against source by legality_spec.rb: the keys must still be the
  # columns the matching services join on.

  # What each piece of carried state is matched by when Lago looks for it after the change.
  CARRIED_STATE_KEYS = {
    "progressive_billing_credit" => %w[charge_id charge_filter_id grouped_by],
    "paid_advance_fee" => %w[charge_id pay_in_advance_event_id],
    "credit_note_balance" => %w[customer_id],
    "wallet_balance" => %w[customer_id],
    "coupon_application" => %w[customer_id plan_id billable_metric_id],
    "commitment_progress" => %w[plan_id]
  }.freeze

  # What each churn rewrites.
  CHURN_REWRITES = {
    "plan-override" => %w[plan_id charge_id charge_filter_id],
    "subscription-override" => %w[charge_id pay_in_advance_event_id],
    "charge-replaced" => %w[charge_id],
    "plan-upgrade" => %w[plan_id charge_id],
    "filter-changed" => %w[charge_filter_id],
    "metric-deleted" => %w[billable_metric_id charge_id]
  }.freeze

  def churns
    CHURN_REWRITES.keys
  end

  def carried_states
    CARRIED_STATE_KEYS.keys
  end

  # ------------------------------------------------------------------ constraints

  def constraint(name, cell)
    case name.to_s
    when "charge_model_x_aggregation" then charge_model_x_aggregation?(cell)
    when "pay_in_advance_charge" then pay_in_advance_charge?(cell)
    when "prorated_charge" then prorated_charge?(cell)
    when "fixed_charge" then fixed_charge?(cell)
    when "subscription_lifecycle" then subscription_lifecycle?(cell)
    when "interacting_pair" then interacting_pair?(cell)
    when "observable_after_mutation" then observable_after_mutation?(cell)
    when "duplicable" then duplicable?(cell)
    when "identity_at_risk" then identity_at_risk?(cell)
    when "none", "" then true
    else raise ArgumentError, "unknown golden constraint #{name.inspect}"
    end
  end

  # A churn can only lose carried state if it rewrites one of the columns that state is found by;
  # where the two do not overlap there is nothing to break.
  def identity_at_risk?(cell)
    keys = CARRIED_STATE_KEYS.fetch(cell[:carried_state].to_s, [])
    rewritten = CHURN_REWRITES.fetch(cell[:churn].to_s, [])

    keys.intersect?(rewritten)
  end

  # Only a feature drawing on a finite pool can be `capped`; everything else simply adds.
  def duplicable?(cell)
    return true unless cell[:arrangement].to_s == "capped"

    cappable?(cell[:feature])
  end

  # A mutation is only observable through a surface that still exists when it happens: a finalized
  # invoice has no draft and cannot be regenerated. A preview and `final` stay legal throughout.
  FINALIZED_ONLY_SURFACES = %w[draft regenerated].freeze

  def observable_after_mutation?(cell)
    return true unless cell[:stage].to_s == "after-finalize"

    FINALIZED_ONLY_SURFACES.exclude?(cell[:observed_via].to_s)
  end

  # Charge#validate_dynamic (charge.rb:144-149), #validate_custom (charge.rb:191-196), and the
  # latest_agg rejection in Charges::Validators::PercentageService (:23-27) and
  # GraduatedPercentageService (:32-36).
  def charge_model_x_aggregation?(cell)
    charge_model = cell[:charge_model].to_sym
    aggregation = cell[:aggregation].to_sym

    case charge_model
    when :dynamic then aggregation == :sum_agg
    when :custom then aggregation == :custom_agg
    when :percentage, :graduated_percentage then aggregation != :latest_agg
    else true
    end
  end

  # Charge#validate_pay_in_advance (charge.rb:154-160): rejected for any volume charge, and for any
  # metric outside AGGREGATION_TYPES_PAYABLE_IN_ADVANCE.
  def pay_in_advance_charge?(cell)
    return false unless charge_model_x_aggregation?(cell)
    return false if cell[:charge_model].to_sym == :volume

    payable_in_advance.include?(cell[:aggregation].to_sym)
  end

  # Charge#validate_prorated (charge.rb:178-189). weighted_sum_agg is always rejected (it already
  # prorates); a non-recurring metric is always rejected; recurring metrics allow standard only when
  # paying in advance, and standard/volume/graduated when paying in arrears.
  def prorated_charge?(cell)
    return false unless charge_model_x_aggregation?(cell)

    aggregation = cell[:aggregation].to_sym
    charge_model = cell[:charge_model].to_sym
    return false if aggregation == :weighted_sum_agg
    return false unless truthy?(cell[:recurring])
    return false unless recurring_capable.include?(aggregation)

    if truthy?(cell[:pay_in_advance])
      charge_model == :standard
    else
      %i[standard volume graduated].include?(charge_model)
    end
  end

  # An unordered pair of features that can actually interact. Two producers are excluded: they simply
  # add to fees_amount_cents, with no stage between them and no order to assert.
  def interacting_pair?(cell)
    first = cell[:feature_a].to_s
    second = cell[:feature_b].to_s

    return false unless first < second # unordered: one cell per pair, and no self-pairs

    reducer?(first) || reducer?(second)
  end

  # Subscription#validates :on_termination_credit_note, absence: true, if: pay_in_arrears?
  # (subscription.rb:80), so `none` is the only legal value on an arrears plan — hence that axis lists
  # `none` explicitly rather than deriving straight from ON_TERMINATION_CREDIT_NOTES.
  def subscription_lifecycle?(cell)
    credit_note = cell[:on_termination_credit_note].to_s
    return true if credit_note == "none"

    truthy?(cell[:plan_pay_in_advance])
  end

  # FixedCharge validation (app/models/fixed_charge.rb:79-97): pay_in_advance is invalid with
  # volume, and prorated is invalid with graduated + pay_in_advance.
  def fixed_charge?(cell)
    charge_model = cell[:charge_model].to_sym
    advance = truthy?(cell[:pay_in_advance])
    prorated = truthy?(cell[:prorated])

    return false if advance && charge_model == :volume
    return false if prorated && advance && charge_model == :graduated

    true
  end

  def truthy?(value)
    [true, "true", "yes"].include?(value)
  end
end
