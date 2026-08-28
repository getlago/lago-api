# frozen_string_literal: true

require "rails_helper"

# Anti-drift guard for the coverage denominator.
#
# GoldenLegality restates a handful of Charge/FixedCharge validation rules so the ledger can compute
# which cells are legal without instantiating everything. That restatement is the one place the
# golden suite duplicates implementation, so it is checked against the real validations here: every
# cell of the charge_model × aggregation product is built as an actual Charge and its validity
# compared with the predicate.
#
# If this spec fails, the rules moved. Fix GoldenLegality (and the affected rows) — do not relax the
# spec. A wrong denominator makes every coverage percentage in COVERAGE.md a lie.
describe "Golden legality agreement" do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }

  def build_metric(aggregation, recurring: false)
    attributes = {organization:, aggregation_type: aggregation.to_s, recurring:}

    case aggregation.to_sym
    when :count_agg then attributes
    when :custom_agg then attributes[:custom_aggregator] = "def aggregate(event, agg, aggregation_properties); agg; end"
    when :weighted_sum_agg
      attributes[:field_name] = "amount"
      attributes[:weighted_interval] = "seconds"
    else attributes[:field_name] = "amount"
    end

    build(:billable_metric, **attributes)
  end

  # A cell is reachable only if BOTH the metric and the charge can exist. Validating just the charge
  # would call e.g. `recurring: true` on a count_agg metric legal, because Charge#validate_prorated
  # reads billable_metric.recurring? without caring that BillableMetric#validate_recurring forbids
  # that metric from existing at all.
  def cell_errors(charge_model:, aggregation:, recurring: false, pay_in_advance: false, prorated: false)
    metric = build_metric(aggregation, recurring:)
    return {metric: metric.errors.to_hash} unless metric.valid?

    properties = ChargeModels::BuildDefaultPropertiesService.call(charge_model) || {}
    charge = build(
      :charge,
      plan:,
      organization:,
      billable_metric: metric,
      charge_model: charge_model.to_s,
      properties:,
      pay_in_advance:,
      prorated:
    )
    charge.valid? ? {} : charge.errors.to_hash
  end

  # graduated_percentage is licence-gated rather than illegal, so the whole product is exercised
  # under a premium licence; the gate itself is covered by a B14 row.
  def compare(recurring: false, pay_in_advance: false, prorated: false)
    disagreements = []

    lago_premium! do
      GoldenLegality.domain(:charge_models).each do |charge_model|
        GoldenLegality.domain(:aggregations).each do |aggregation|
          cell = {charge_model:, aggregation:, recurring: recurring.to_s, pay_in_advance: pay_in_advance.to_s}
          expected = yield(cell)
          errors = cell_errors(charge_model:, aggregation:, recurring:, pay_in_advance:, prorated:)
          actual = errors.empty?

          next if expected == actual
          disagreements << "#{charge_model}/#{aggregation}: GoldenLegality says " \
                           "#{expected ? "legal" : "illegal"}, Lago says #{actual ? "valid" : errors.inspect}"
        end
      end
    end

    disagreements
  end

  it "agrees with Charge validation on the charge_model x aggregation product" do
    disagreements = compare { |cell| GoldenLegality.charge_model_x_aggregation?(cell) }

    expect(disagreements).to be_empty,
      "#{disagreements.size} cell(s) disagree — update GoldenLegality, not this spec:\n- #{disagreements.join("\n- ")}"
  end

  it "agrees with Charge validation on pay_in_advance" do
    disagreements = compare(pay_in_advance: true) { |cell| GoldenLegality.pay_in_advance_charge?(cell) }

    expect(disagreements).to be_empty,
      "#{disagreements.size} cell(s) disagree — update GoldenLegality, not this spec:\n- #{disagreements.join("\n- ")}"
  end

  it "agrees with Charge validation on prorated, for recurring metrics billed in arrears" do
    disagreements = compare(recurring: true, prorated: true) do |cell|
      GoldenLegality.prorated_charge?(cell)
    end

    expect(disagreements).to be_empty,
      "#{disagreements.size} cell(s) disagree — update GoldenLegality, not this spec:\n- #{disagreements.join("\n- ")}"
  end

  it "agrees with Charge validation on prorated, for recurring metrics billed in advance" do
    disagreements = compare(recurring: true, prorated: true, pay_in_advance: true) do |cell|
      GoldenLegality.prorated_charge?(cell)
    end

    expect(disagreements).to be_empty,
      "#{disagreements.size} cell(s) disagree — update GoldenLegality, not this spec:\n- #{disagreements.join("\n- ")}"
  end

  # B15's feature list is the one domain DECLARED rather than derived, because no constant enumerates
  # the pipeline's stages: each reducer must still be invoked, and still in the declared order.
  #
  # If this fails the pipeline was reordered, and every B15 row's `math` is now suspect. Fix the order
  # in GoldenLegality and re-derive the rows; do not relax the spec.
  describe "billing feature pipeline" do
    let(:source) { File.read(Rails.root.join("app/services/invoices/calculate_fees_service.rb")) }

    # The call site that implements each reducer, in the order GoldenLegality declares them.
    let(:reducer_call_sites) do
      {
        "progressive_billing" => "Credits::ProgressiveBillingService",
        "coupon" => "Credits::AppliedCouponsService",
        "tax" => "Invoices::ComputeTaxesAndTotalsService",
        "credit_note" => "create_credit_note_credit",
        "prepaid_credit" => "create_applied_prepaid_credit"
      }
    end

    it "still invokes every reducer it claims" do
      missing = reducer_call_sites.reject { |_feature, call| source.include?(call) }

      expect(missing).to be_empty,
        "GoldenLegality names reducer(s) #{missing.keys.inspect} whose call site is gone from " \
        "CalculateFeesService. B15 is asserting interactions with a stage that no longer runs."
    end

    it "still runs them in the declared order" do
      expect(GoldenLegality::BILLING_FEATURE_REDUCERS).to eq(reducer_call_sites.keys),
        "the declared reducer order and this spec's call-site map have diverged"

      positions = reducer_call_sites.transform_values { |call| source.index(call) }

      expect(positions.values).to eq(positions.values.sort),
        "CalculateFeesService applies reducers in a different order than GoldenLegality declares. " \
        "Found: #{positions.sort_by { |_f, i| i }.map(&:first).inspect}, " \
        "declared: #{GoldenLegality::BILLING_FEATURE_REDUCERS.inspect}. Every B15 row reasons about " \
        "this order, so their expected values are now suspect."
    end
  end

  # B19 claims two instances of the same feature are ORDERED, and every row in it reasons about that
  # order. Each ordering is a single clause in a single service — the kind of thing a refactor drops
  # silently, leaving the rows passing on coincidence — so each is checked against its source.
  describe "multiplicity ordering" do
    let(:orderings) do
      {
        "coupon" => ["app/services/credits/applied_coupons_service.rb",
          "coupons.limited_billable_metrics DESC, coupons.limited_plans DESC, applied_coupons.created_at ASC"],
        "prepaid_credit" => ["app/services/credits/allocate_prepaid_credits_by_wallets_service.rb",
          "in_application_order"],
        "credit_note" => ["app/services/credits/credit_note_service.rb",
          "credit_notes"]
      }
    end

    it "still orders every cappable feature it claims to" do
      missing = orderings.reject do |_feature, (path, clause)|
        File.read(Rails.root.join(path)).include?(clause)
      end

      expect(missing).to be_empty,
        "the ordering B19 relies on is gone for #{missing.keys.inspect}. Rows in that block reason " \
        "about which of two instances is consumed first; without the clause they assert a coincidence."
    end

    it "claims an ordering for every cappable feature" do
      expect(GoldenLegality::CAPPABLE_FEATURES).to match_array(orderings.keys),
        "a feature that draws on a finite pool has an allocation order, so it needs an entry here — " \
        "otherwise B19's `capped` cells for it are unguarded."
    end

    it "only calls a feature cappable when it draws on a pool" do
      expect(GoldenLegality::CAPPABLE_FEATURES - GoldenLegality::DUPLICABLE_FEATURES).to be_empty
    end
  end

  # B10's denominator rests on a claim about reachability rather than on a validator, so it is proved
  # from BOTH ends: the source says only one place can build such a fee, and a real one-off invoice
  # with an active coupon shows the coupon is never consulted.
  #
  # If any of these fails the exclusion is no longer true and those 12 cells are real work again —
  # delete GoldenLegality#coupon_with_one_off_only_tax_level? rather than relaxing the spec.
  describe "one-off-only tax levels cannot carry a coupon" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:customer) { create(:customer, organization:, billing_entity:, currency: "EUR") }
    let(:add_on_tax) { create(:tax, organization:, rate: 10) }
    let(:add_on) { create(:add_on, organization:, amount_cents: 10_000) }
    let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_cents: 5_000, frequency: "once") }

    it "assigns fee_type add_on in exactly one place, on the one-off path" do
      assignments = Dir[Rails.root.join("app/**/*.rb")].select do |path|
        File.read(path).include?("fee_type: :add_on")
      end

      expect(assignments.map { |path| Pathname(path).relative_path_from(Rails.root).to_s })
        .to eq(["app/services/fees/one_off_service.rb"]),
        "`tax_level: add-on` is excluded from B10 because only a one-off invoice can carry an add_on " \
        "fee. Another service now builds one, so the exclusion is wrong."
    end

    it "passes explicit tax_codes to Fees::ApplyTaxesService from exactly one place" do
      callers = Dir[Rails.root.join("app/**/*.rb")].select do |path|
        File.read(path).include?("Fees::ApplyTaxesService.call(fee:, tax_codes:")
      end

      expect(callers.map { |path| Pathname(path).relative_path_from(Rails.root).to_s })
        .to eq(["app/services/fees/one_off_service.rb"]),
        "`tax_level: explicit-codes` is the first rung of the ApplyTaxesService ladder and is excluded " \
        "from B10 because only the one-off path supplies tax_codes. Another caller now does."
    end

    it "never mentions a coupon anywhere in the one-off invoice service" do
      source = File.read(Rails.root.join("app/services/invoices/create_one_off_service.rb"))

      expect(source.downcase).not_to include("coupon"),
        "Invoices::CreateOneOffService now references coupons, so a coupon may reach a one-off " \
        "invoice and B10's 12 excluded cells are writeable again."
    end

    it "leaves an active coupon untouched by a one-off invoice, and taxes the fee from the add-on" do
      create(:add_on_applied_tax, add_on:, tax: add_on_tax)
      applied_coupon = create(:applied_coupon, customer:, coupon:, amount_cents: 5_000)
      CurrentContext.source = "graphql" # add_on_id rather than add_on_code

      result = Invoices::CreateOneOffService.call(
        customer:,
        currency: "EUR",
        fees: [{add_on_id: add_on.id, units: 1, unit_amount_cents: 10_000}],
        timestamp: Time.current.to_i
      )

      expect(result).to be_success
      invoice = result.invoice
      fee = invoice.fees.sole

      # The fee IS an add-on fee taxed at the add-on rung of the ladder, so the cell's tax_level really
      # is reachable and the coupon half of it is the load-bearing claim.
      expect(fee.fee_type).to eq("add_on")
      expect(fee.applied_taxes.map(&:tax_code)).to eq([add_on_tax.code])

      # And the coupon simply does not participate: no coupon credit, no money moved, and the
      # applied coupon still active and unconsumed for the next invoice.
      expect(invoice.credits.coupon_kind).to be_empty
      expect(invoice.coupons_amount_cents).to eq(0)
      expect(invoice.total_amount_cents).to eq(11_000)
      expect(applied_coupon.reload).to be_active
      expect(applied_coupon.amount_cents).to eq(5_000)
    end

    it "excludes exactly B10's twelve coupon x one-off-tax-level cells" do
      block = GoldenLedger.block_by_id("B10")
      candidates = GoldenLedger.candidate_cells(block)
      excluded = candidates.reject { |cell| GoldenLegality.api_reachable?(cell.symbolize_keys) }

      expect(candidates.size).to eq(48)
      expect(excluded.size).to eq(12)
      expect(excluded.map { |cell| cell["tax_level"] }.uniq.sort).to eq(["add-on", "explicit-codes"])
      expect(GoldenLedger.legal_cells(block).size).to eq(36)
    end

    it "keeps every tax_level legal for a cell that carries no coupon" do
      GoldenLegality::ONE_OFF_ONLY_TAX_LEVELS.each do |level|
        expect(GoldenLegality.api_reachable?({tax_level: level})).to be(true),
          "the exclusion is about the COMBINATION; a couponless block using tax_level #{level} must " \
          "keep it"
      end
    end
  end

  # If any of these fails, an add-on fee has become observable through a surface other than a
  # finalized invoice and those 4 B19 cells are real work again — delete
  # GoldenLegality#add_on_fee_on_unreachable_surface? rather than relaxing the spec.
  describe "an add-on fee is observable on a finalized invoice only" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:customer) { create(:customer, organization:, billing_entity:, currency: "EUR") }
    let(:add_on) { create(:add_on, organization:, amount_cents: 10_000) }

    it "permits no fees at all on the preview route" do
      source = File.read(Rails.root.join("app/controllers/api/v1/invoices_controller.rb"))
      preview_params = source[/def preview_params.*?\n      end/m]

      expect(preview_params).not_to be_nil,
        "InvoicesController#preview_params is gone, so the shape of the preview payload is no longer " \
        "known and the exclusion cannot be justified from it"
      expect(preview_params).not_to include("add_on"),
        "the preview route now names add-ons, so B19's add_on/*/preview cells may be writeable"
      expect(preview_params).not_to match(/^\s+fees:/),
        "the preview route now accepts a fees array, so B19's add_on/*/preview cells may be writeable"
    end

    it "produces no add-on fee anywhere in the preview services" do
      sources = Dir[Rails.root.join("app/services/invoices/preview_service.rb")] +
        Dir[Rails.root.join("app/services/invoices/preview/**/*.rb")]

      expect(sources).not_to be_empty
      offenders = sources.select { |path| File.read(path).match?(/add_on|one_off/) }

      expect(offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }).to be_empty,
        "a preview service now knows about add-ons or one-off invoices, so a previewed add-on fee " \
        "may be producible"
    end

    it "refuses to refresh a one-off invoice, which is never a draft in the first place" do
      CurrentContext.source = "graphql" # add_on_id rather than add_on_code

      result = Invoices::CreateOneOffService.call(
        customer:,
        currency: "EUR",
        fees: [{add_on_id: add_on.id, units: 1, unit_amount_cents: 10_000}],
        timestamp: Time.current.to_i
      )

      expect(result).to be_success
      invoice = result.invoice

      # Never a draft: only Invoices::SubscriptionService consults the grace period, so the one-off
      # path finalizes immediately and there is no draft for `regenerated` to observe.
      expect(invoice.invoice_type).to eq("one_off")
      expect(invoice).to be_finalized
      expect(invoice.fees.map(&:fee_type)).to eq(["add_on"])

      # And the refresh route refuses it even so.
      refresh = Invoices::RefreshDraftService.call(invoice:)
      expect(refresh).to be_failure
      expect(refresh.error).to be_a(BaseService::ForbiddenFailure)
    end

    it "excludes exactly B19's four add-on-fee surface cells" do
      block = GoldenLedger.block_by_id("B19")
      candidates = GoldenLedger.candidate_cells(block)
      excluded = candidates.reject { |cell| GoldenLegality.api_reachable?(cell.symbolize_keys) }

      expect(excluded.size).to eq(4)
      expect(excluded.map { |cell| cell["feature"] }.uniq).to eq(["add_on"])
      expect(excluded.map { |cell| cell["observed_via"] }.sort)
        .to eq(%w[preview preview regenerated regenerated])
    end

    it "leaves every other feature's surfaces alone, and add_on's finalized invoice" do
      # SURFACES is draft/regenerated/preview — every surface that is NOT a finalized invoice — so
      # add_on is the one feature for which none of them is reachable.
      GoldenLegality.duplicable_features.each do |feature|
        GoldenLegality::SURFACES.each do |surface|
          expect(GoldenLegality.api_reachable?({feature:, observed_via: surface}))
            .to be(feature != "add_on"), "feature #{feature} observed via #{surface}"
        end
      end

      expect(GoldenLegality.api_reachable?({feature: "add_on", observed_via: "invoice"})).to be(true)
    end

    it "does not touch a block that has no feature axis" do
      # The exclusion is keyed on the pair; B10 is the block whose denominator a loosely-keyed
      # predicate would move, because it names one-off-only tax levels without naming a feature.
      expect(GoldenLegality.add_on_fee_on_unreachable_surface?({tax_level: "add-on"})).to be(false)
      expect(GoldenLedger.legal_cells(GoldenLedger.block_by_id("B10")).size).to eq(36)
    end
  end

  it "derives every block axis domain without error" do
    GoldenLedger.blocks.each do |block|
      block["axes"].each do |name, spec|
        values = GoldenLedger.axis_values(spec)
        expect(values).not_to be_empty, "#{block["id"]} axis #{name} resolved to an empty domain"
      end
    end
  end
end
