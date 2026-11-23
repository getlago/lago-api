# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::ConvertPlansService do
  subject(:result) { described_class.call(migration:, dry_run:) }

  let_it_be(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_fr") }
  let_it_be(:billable_metric) { create(:sum_billable_metric, organization:, code: "api_calls", name: "API calls") }
  let_it_be(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
  let_it_be(:plan) do
    create(
      :plan,
      organization:,
      code: "pro_monthly",
      name: "Pro",
      invoice_display_name: "Pro plan",
      description: "Pro monthly",
      interval: "monthly",
      amount_cents: 10_000,
      amount_currency: "EUR",
      pay_in_advance: true,
      created_at: Time.zone.parse("2026-01-10T08:30:00Z")
    )
  end
  let_it_be(:add_on) { create(:add_on, organization:, code: "onboarding", name: "Onboarding", invoice_display_name: nil) }
  let_it_be(:fixed_charge) do
    create(:fixed_charge, plan:, add_on:, code: "onboarding_fee", units: 2, properties: {amount: "50"}, invoice_display_name: nil)
  end
  let_it_be(:charge) do
    create(
      :volume_charge,
      plan:,
      billable_metric:,
      code: "api_calls_charge",
      invoice_display_name: nil,
      min_amount_cents: 500
    )
  end
  let_it_be(:charge_filter) do
    create(
      :charge_filter,
      charge:,
      code: "region_eu",
      invoice_display_name: "EU calls",
      properties: {volume_ranges: [{from_value: 0, to_value: 50, per_unit_amount: "3", flat_amount: "0"}, {from_value: 51, to_value: nil, per_unit_amount: "2", flat_amount: "0"}]}
    )
  end

  let(:shadow_organization) { create(:organization) }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping:) }
  let(:plan_mapping) { {"pro_monthly" => "pro_monthly_v2"} }
  let(:status) { "shadowing" }
  let(:dry_run) { false }

  before_all do
    create(:plan_applied_tax, plan:, tax:)
    create(:charge_applied_tax, charge:, tax:)
    create(:charge_filter_value, charge_filter:, billable_metric_filter: metric_filter, values: ["eu"])
  end

  before do
    create(:tax, organization: shadow_organization, code: "vat_fr")
    shadow_metric = create(:sum_billable_metric, organization: shadow_organization, code: "api_calls")
    create(:billable_metric_filter, billable_metric: shadow_metric, key: "region", values: %w[eu us])
  end

  def plan_rate_card(code)
    shadow_organization.rate_cards.find_by!(code:).plan_applied_rate_cards.sole
  end

  it "creates the catalog plan with a rate card for the subscription fee, each fixed charge, charge and charge filter" do
    expect(result).to be_success
    expect(result.plans.map { [it.plan_code, it.catalog_plan_code, it.outcome, it.error] })
      .to eq([["pro_monthly", "pro_monthly_v2", :created, nil]])

    catalog_plan = shadow_organization.catalog_plans.find_by!(code: "pro_monthly_v2")
    expect(catalog_plan).to have_attributes(name: "Pro", invoice_display_name: "Pro plan", description: "Pro monthly", currency: "EUR")
    expect(catalog_plan.taxes.map(&:code)).to eq(["vat_fr"])
    expect(catalog_plan.applied_rate_cards.map { it.rate_card.code }).to match_array(
      %w[pro_monthly_v2_subscription_fee pro_monthly_v2_onboarding_fee pro_monthly_v2_api_calls_charge pro_monthly_v2_api_calls_charge_region_eu]
    )
  end

  it "prices the subscription fee with a fixed product of the plan" do
    result

    subscription_fee = plan_rate_card("pro_monthly_v2_subscription_fee")
    expect(subscription_fee.units).to eq(1)
    expect(subscription_fee.product).to have_attributes(code: "pro_monthly_v2_subscription_fee", product_type: "fixed", name: "Pro", invoice_display_name: "Pro plan")
    expect(subscription_fee.rate_card).to have_attributes(billing_timing: "advance", proration: true, currency: "EUR")
    expect(subscription_fee.rate_card.rates.sole).to have_attributes(
      code: "v1",
      effective_from: Time.zone.parse("2026-01-10T08:30:00Z"),
      rate_model: "standard",
      rate_properties: {"amount" => "100.0"}, # 10_000 cents
      billing_interval_unit: "month",
      billing_interval_count: 1
    )
  end

  it "prices each fixed charge with a fixed product of its add-on" do
    result

    onboarding = plan_rate_card("pro_monthly_v2_onboarding_fee")
    expect(onboarding.units).to eq(2)
    expect(onboarding.product).to have_attributes(code: "onboarding", product_type: "fixed", name: "Onboarding")
    expect(onboarding.rate_card).to have_attributes(billing_timing: "arrears", proration: false)
    expect(onboarding.rate_card.rates.sole).to have_attributes(
      effective_from: Time.zone.parse("2026-01-10T00:00:00Z"),
      rate_model: "standard",
      rate_properties: {"amount" => "50"}
    )
  end

  it "reports the charge minimum that cannot cover the charge filters" do
    expect(result.plans.sole.gaps).to eq(["charge api_calls_charge: min_amount_cents with filters"])
  end

  it "prices each charge and charge filter with a metered product of the shadow billable metric" do
    result

    default_card = plan_rate_card("pro_monthly_v2_api_calls_charge").rate_card
    product = default_card.product
    expect(product).to have_attributes(
      code: "api_calls",
      product_type: "metered",
      name: "API calls",
      billable_metric: shadow_organization.billable_metrics.find_by!(code: "api_calls")
    )
    expect(default_card).to have_attributes(product_filter: nil, billing_timing: "arrears", display_on_invoice: true)
    expect(default_card.taxes.map(&:code)).to eq(["vat_fr"])
    expect(default_card.rates.sole).to have_attributes(
      rate_model: "volume",
      min_amount_cents: 500,
      rate_properties: {
        "volume_ranges" => [
          {"from_value" => 0, "to_value" => 100, "per_unit_amount" => "2", "flat_amount" => "1"},
          {"from_value" => 100, "to_value" => nil, "per_unit_amount" => "1", "flat_amount" => "0"}
        ]
      }
    )

    filter_card = plan_rate_card("pro_monthly_v2_api_calls_charge_region_eu").rate_card
    expect(filter_card.product).to eq(product)
    expect(filter_card.product_filter).to have_attributes(code: "region_eu", invoice_display_name: "EU calls")
    expect(filter_card.product_filter.to_h).to eq({"region" => ["eu"]})
    expect(filter_card.rates.sole.rate_properties["volume_ranges"].map { it["from_value"] }).to eq([0, 50])
    expect(filter_card.rates.sole.min_amount_cents).to eq(0)
  end

  context "when a subscription started before the plan was created" do
    before do
      create(
        :subscription,
        plan:,
        customer: create(:customer, organization:),
        started_at: Time.zone.parse("2025-12-01T00:00:00Z"),
        subscription_at: Time.zone.parse("2025-11-15T00:00:00Z")
      )
    end

    it "makes the rates effective from the earliest subscription date" do
      result

      expect(plan_rate_card("pro_monthly_v2_subscription_fee").rate_card.rates.sole.effective_from)
        .to eq(Time.zone.parse("2025-11-15T00:00:00Z"))
    end
  end

  context "when another plan charges the same billable metric without its filters" do
    let(:plan_mapping) { {"pro_monthly" => "pro_monthly_v2", "pro_yearly" => "pro_yearly_v2"} }

    before do
      yearly = create(:plan, organization:, code: "pro_yearly", interval: "yearly", amount_currency: "EUR", bill_charges_monthly: true)
      create(:standard_charge, plan: yearly, billable_metric:, code: "api_calls_charge", invoice_display_name: nil)
    end

    it "prices it on a product of its own and bills its charges monthly" do
      expect(result.plans.map(&:outcome)).to eq(%i[created created])

      yearly_card = shadow_organization.rate_cards.find_by!(code: "pro_yearly_v2_api_calls_charge")
      expect(yearly_card.product).to have_attributes(code: "pro_yearly_v2_api_calls_charge", product_type: "metered")
      expect(yearly_card.product.filters).to be_empty
      expect(shadow_organization.rate_cards.find_by!(code: "pro_monthly_v2_api_calls_charge").product.code).to eq("api_calls")
      expect(yearly_card.rates.sole).to have_attributes(billing_interval_unit: "month", billing_interval_count: 1)
      expect(shadow_organization.rate_cards.find_by!(code: "pro_yearly_v2_subscription_fee").rates.sole)
        .to have_attributes(billing_interval_unit: "year", billing_interval_count: 1)
    end

    it "bills an event matching the other plan's filter on its default rate card" do
      result

      rate_card = shadow_organization.rate_cards.find_by!(code: "pro_yearly_v2_api_calls_charge")
      contract_rate_card = create(:contract_rate_card, organization: shadow_organization, rate_card:)
      billing_segment = build(
        :billing_segment,
        organization: shadow_organization,
        customer: contract_rate_card.contract.customer,
        contract: contract_rate_card.contract,
        contract_rate_card:,
        rate_card_rate: rate_card.rates.sole
      )
      event = build(
        :event,
        organization_id: shadow_organization.id,
        external_subscription_id: contract_rate_card.contract.external_id,
        code: "api_calls",
        properties: {"region" => "eu"}
      )

      buckets = Fees::ChargeService::Sources::BillingSegment.new(billing_segment:).pricing_buckets(event:)
      expect(buckets.map(&:product_filter)).to eq([nil])
    end
  end

  context "when another plan charges the same billable metric with the same filters" do
    let(:plan_mapping) { {"pro_monthly" => "pro_monthly_v2", "pro_yearly" => "pro_yearly_v2"} }

    before do
      yearly = create(:plan, organization:, code: "pro_yearly", interval: "yearly", amount_currency: "EUR")
      yearly_charge = create(:standard_charge, plan: yearly, billable_metric:, code: "api_calls_charge", invoice_display_name: nil)
      yearly_filter = create(:charge_filter, charge: yearly_charge, code: "eu_only", properties: {amount: "1"})
      create(:charge_filter_value, charge_filter: yearly_filter, billable_metric_filter: metric_filter, values: ["eu"])
    end

    it "reuses the product and its filter" do
      expect(result.plans.map(&:outcome)).to eq(%i[created created])

      product = shadow_organization.products.find_by!(code: "api_calls")
      expect(product.filters.map(&:code)).to eq(["region_eu"])
      expect(shadow_organization.rate_cards.find_by!(code: "pro_yearly_v2_api_calls_charge_eu_only"))
        .to have_attributes(product:, product_filter: product.filters.sole)
    end
  end

  context "when the shadow product of the charge has a filter the plan does not price" do
    before do
      shadow_metric = shadow_organization.billable_metrics.find_by!(code: "api_calls")
      %w[api_calls pro_monthly_v2_api_calls_charge].each do |code|
        product = create(:product, organization: shadow_organization, billable_metric: shadow_metric, code:)
        product_filter = create(:product_filter, organization: shadow_organization, product:)
        create(:product_filter_value, organization: shadow_organization, product_filter:, billable_metric_filter: shadow_metric.filters.sole, value: "us")
      end
    end

    it "reports the error and rolls the whole plan back" do
      expect(result.plans.sole).to have_attributes(outcome: :failed, error: "product_has_unpriced_filters: pro_monthly_v2_api_calls_charge")
      expect(shadow_organization.catalog_plans).to be_empty
      expect(shadow_organization.rate_cards).to be_empty
    end
  end

  context "when the plan has fields that the product catalog does not implement", :premium do
    let(:plan_mapping) { {"basic" => "basic_v2"} }
    let(:dry_run) { true }

    before do
      basic = create(:plan, organization:, code: "basic", amount_currency: "EUR", trial_period: 14)
      create(:commitment, plan: basic)
      create(:usage_threshold, plan: basic)
      create(:standard_charge, plan: basic, billable_metric:, code: "calls", invoice_display_name: "Calls", accepts_target_wallet: true)
      create(:fixed_charge, plan: basic, add_on:, code: "setup", invoice_display_name: "Setup")
    end

    it "lists them" do
      expect(result.plans.sole.gaps).to eq(
        [
          "trial_period",
          "minimum_commitment",
          "progressive_billing_thresholds",
          "charge calls: accepts_target_wallet",
          "charge calls: invoice_display_name",
          "fixed_charge setup: invoice_display_name"
        ]
      )
    end
  end

  context "when DRY_RUN is enabled" do
    let(:dry_run) { true }

    it "lists the rate cards it would create and writes nothing" do
      expect(result.plans.sole).to have_attributes(outcome: :would_create)
      expect(result.plans.sole.entries.map { it.rate_card[:code] }).to eq(
        %w[pro_monthly_v2_subscription_fee pro_monthly_v2_onboarding_fee pro_monthly_v2_api_calls_charge pro_monthly_v2_api_calls_charge_region_eu]
      )

      expect(shadow_organization.catalog_plans).to be_empty
      expect(shadow_organization.products).to be_empty
      expect(shadow_organization.rate_cards).to be_empty
    end
  end

  context "when the catalog plan already exists" do
    before { create(:catalog_plan, organization: shadow_organization, code: "pro_monthly_v2") }

    it "skips the plan" do
      expect(result.plans.sole.outcome).to eq(:skipped)
      expect(shadow_organization.products).to be_empty
    end
  end

  context "when the plan does not exist" do
    let(:plan_mapping) { {"unknown" => "unknown_v2"} }

    it "reports it as failed" do
      expect(result.plans.sole).to have_attributes(outcome: :failed, error: "plan_not_found")
    end
  end

  context "when a billable metric is not copied to the shadow organization" do
    before { shadow_organization.billable_metrics.find_by!(code: "api_calls").discard! }

    it "reports the missing billable metrics and creates nothing" do
      expect(result.plans.sole).to have_attributes(outcome: :failed, error: "billable_metrics_not_copied: api_calls")
      expect(shadow_organization.catalog_plans).to be_empty
    end
  end

  context "when a product code is taken by another kind of product" do
    before { create(:product, :fixed, organization: shadow_organization, code: "api_calls") }

    it "reports the error and rolls the whole plan back" do
      expect(result.plans.sole).to have_attributes(outcome: :failed, error: "product_exists_with_another_type_or_metric: api_calls")

      expect(shadow_organization.catalog_plans).to be_empty
      expect(shadow_organization.products.pluck(:code)).to eq(["api_calls"])
      expect(shadow_organization.rate_cards).to be_empty
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "converts nothing" do
      expect(result.plans).to eq([])
      expect(shadow_organization.catalog_plans).to be_empty
    end
  end
end
