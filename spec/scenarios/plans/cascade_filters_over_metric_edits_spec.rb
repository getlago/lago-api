# frozen_string_literal: true

require "rails_helper"

# Walks a plan and its override through metric edits and plan edits, checking both sides
# after every step. Each step lists the filters before and after, written out in full as
# `{key: [values]} @price`, so the state is readable without running anything.
#
# Three things are pinned here:
#   - filters left on a shared predicate by a metric edit are NOT deleted for the customer
#   - a price negotiated on the override is NOT overwritten by a plan reprice. Note this holds
#     for a reprice only: widening a filter's values replaces the filter rather than editing it,
#     and the replacement is created with the plan's price, so the negotiated one is lost.
#   - whatever the plan ends up with, the override follows
#
# Removing a metric value trims the value out of the charge filters referencing it rather
# than destroying them, so predicates shorten and can collide. That is existing behaviour.
RSpec.describe "Cascade filters over metric edits", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "api_pages", field_name: "value") }

  let(:models) { (1..10).map { "m#{it}" } }

  let(:pages) { {"type" => %w[pages]} }
  let(:m2) { {"type" => %w[pages], "model" => %w[m2]} }
  let(:m3) { {"type" => %w[pages], "model" => %w[m3]} }
  let(:m4) { {"type" => %w[pages], "model" => %w[m4]} }
  let(:m5) { {"type" => %w[pages], "model" => %w[m5]} }

  before do
    create(:billable_metric_filter, billable_metric:, key: "type", values: %w[pages])
    create(:billable_metric_filter, billable_metric:, key: "model", values: models)
  end

  def model_filter(model, amount)
    {invoice_display_name: "Model #{model}", properties: {amount:}, values: {type: %w[pages], model: [model]}}
  end

  def pages_filter(amount)
    {invoice_display_name: "Pages", properties: {amount:}, values: {type: %w[pages]}}
  end

  def plan_payload(filters, charge_id: nil, cascade: false)
    charge = {
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      code: "pages_charge",
      pay_in_advance: false,
      properties: {amount: "0.01"},
      filters:
    }
    charge[:id] = charge_id if charge_id

    payload = {
      name: "API Plan", code: "api_plan", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false,
      charges: [charge]
    }
    payload[:cascade_updates] = true if cascade
    payload
  end

  def keep_metric_values(kept)
    update_metric(billable_metric, {
      filters: [{key: "type", values: %w[pages]}, {key: "model", values: kept}]
    })
  end

  # Sorted so the comparisons do not depend on the order filters come back in
  def predicates(charge)
    charge.filters.reload.map(&:to_h).sort_by(&:to_s)
  end

  def prices_of(charge, predicate)
    charge.filters.reload.select { it.to_h == predicate }.map { it.properties["amount"] }
  end

  # A plan whose charge carries four single-model filters and one on `type` alone, and a
  # subscription whose charge is overridden, which deep-copies all five onto a child plan
  def setup_plan_with_override
    create_plan(plan_payload([
      model_filter("m1", "1"),
      model_filter("m2", "2"),
      model_filter("m3", "3"),
      model_filter("m5", "5"),
      pages_filter("0.5")
    ]))

    parent_plan = organization.plans.find_by(code: "api_plan")
    parent_charge = parent_plan.charges.find_by(code: "pages_charge")

    create_subscription({
      external_customer_id: customer.external_id,
      external_id: "sub_api",
      plan_code: "api_plan"
    })

    subscription = organization.subscriptions.find_by(external_id: "sub_api")
    update_subscription_charge(subscription, "pages_charge", {properties: {amount: "0.01"}})

    subscription.reload
    {parent_plan:, parent_charge:, subscription:, child_charge: subscription.plan.charges.find_by(code: "pages_charge")}
  end

  # Three edits in a row: two metric edits that collapse filters onto a shared predicate,
  # then one plan edit that adds, reprices, keeps and removes in the same request. Checks
  # the parent and the override after each one.
  it "keeps the override aligned with the plan across successive metric and plan edits" do
    ctx = setup_plan_with_override
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]

    # STEP 0 — the override has just deep-copied the plan's filters, prices included.
    # Parent and child both hold:
    #
    #   {type: [pages], model: [m1]}  @1
    #   {type: [pages], model: [m2]}  @2
    #   {type: [pages], model: [m3]}  @3
    #   {type: [pages], model: [m5]}  @5
    #   {type: [pages]}               @0.5
    expect(predicates(parent_charge).size).to eq(5)
    expect(predicates(child_charge)).to eq(predicates(parent_charge))

    # STEP 1 — metric edit removing m1 and m2 in one go. Their filters lose the `model`
    # key and land on `{type: [pages]}`, keeping their own price. Nothing is deleted, and
    # no cascade runs: the metric edit walks charge_filter_values, which belong to no plan.
    #
    #   parent and child, before      ->  parent and child, after
    #   {type: [pages], model: [m1]} @1   {type: [pages]}              @1
    #   {type: [pages], model: [m2]} @2   {type: [pages]}              @2
    #   {type: [pages], model: [m3]} @3   {type: [pages], model: [m3]} @3
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @5
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    keep_metric_values(models - %w[m1 m2])

    # note: only elements of {type: [pages]} are counted
    expect(predicates(parent_charge).count(pages)).to eq(3)
    expect(predicates(child_charge)).to eq(predicates(parent_charge))

    # STEP 2 — metric edit removing m3 too, so a fourth filter joins the same predicate
    #
    #   parent and child, before      ->  parent and child, after
    #   {type: [pages]}              @1   {type: [pages]}              @1
    #   {type: [pages]}              @2   {type: [pages]}              @2
    #   {type: [pages], model: [m3]} @3   {type: [pages]}              @3
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @5
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    keep_metric_values(models - %w[m1 m2 m3])

    expect(predicates(parent_charge).count(pages)).to eq(4)
    expect(predicates(child_charge)).to eq(predicates(parent_charge))

    # STEP 3 — one plan edit doing all four things at once: `m4` added, `m5` repriced
    # 5 -> 50, `{type: [pages]}` left untouched at 0.5, and the four duplicates dropped.
    # This is the only step that needs the cascade: the override follows if it propagates.
    #
    #   parent and child, before      ->  parent and child, after
    #   {type: [pages]}              @1   (dropped)
    #   {type: [pages]}              @2   (dropped)
    #   {type: [pages]}              @3   (dropped)
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @50
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    #                                     {type: [pages], model: [m4]} @4   (added)
    update_plan(ctx[:parent_plan], plan_payload(
      [model_filter("m4", "4"), model_filter("m5", "50"), pages_filter("0.5")],
      charge_id: parent_charge.id, cascade: true
    ))

    expect(predicates(parent_charge)).to eq([pages, m4, m5].sort_by(&:to_s))
    expect(predicates(child_charge)).to eq(predicates(parent_charge))

    expect(prices_of(parent_charge, m5)).to eq(%w[50])
    expect(prices_of(child_charge, m5)).to eq(%w[50])
    expect(prices_of(child_charge, pages)).to eq(%w[0.5])
  end

  # We do not pick prices for the customer. A price negotiated on the override survives a
  # plan reprice, including when its filter sits on a predicate shared with others, where
  # the cascade has to choose which row survives.
  it "keeps a price negotiated on the override when the plan reprices" do
    ctx = setup_plan_with_override
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]

    # STEP 0 — the customer negotiates `m5` down from 5 to 0.5 on their own plan.
    # Only the child changes here.
    #
    #   parent, unchanged                 child, after the negotiation
    #   {type: [pages], model: [m1]} @1   {type: [pages], model: [m1]} @1
    #   {type: [pages], model: [m2]} @2   {type: [pages], model: [m2]} @2
    #   {type: [pages], model: [m3]} @3   {type: [pages], model: [m3]} @3
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @0.5   <- negotiated
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    child_charge.filters.reload.find { it.to_h == m5 }.update!(properties: {"amount" => "0.5"})

    # STEP 1 — metric edit removing m1 and m2, so `{type: [pages]}` ends up shared by three
    #
    #   parent, after                     child, after
    #   {type: [pages]}              @1   {type: [pages]}              @1
    #   {type: [pages]}              @2   {type: [pages]}              @2
    #   {type: [pages], model: [m3]} @3   {type: [pages], model: [m3]} @3
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @0.5
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    keep_metric_values(models - %w[m1 m2])

    # STEP 2 — the plan reprices everything it still knows about: m3 to 30, m5 to 50 and
    # `{type: [pages]}` to 5. The negotiated 0.5 on the child must not move.
    #
    #   parent, after                     child, after
    #   {type: [pages], model: [m3]} @30  {type: [pages], model: [m3]} @30
    #   {type: [pages], model: [m5]} @50  {type: [pages], model: [m5]} @0.5   <- kept
    #   {type: [pages]}              @5   {type: [pages]}              @5
    update_plan(ctx[:parent_plan], plan_payload(
      [model_filter("m3", "30"), model_filter("m5", "50"), pages_filter("5")],
      charge_id: parent_charge.id, cascade: true
    ))

    expect(prices_of(parent_charge, m5)).to eq(%w[50])
    expect(prices_of(child_charge, m5)).to eq(%w[0.5])
  end

  # Removing a single value collapses only the filter that referenced it. This is the
  # counterpart to the collapse cases: it guards against an over-eager fix that would
  # also delete or rewrite the filters carrying the values that are still allowed.
  it "leaves the untouched filters alone when a single value is removed" do
    ctx = setup_plan_with_override

    # STEP 1 — metric edit removing m1 only. Its filter loses the `model` key and joins
    # `{type: [pages]}`; m2, m3 and m5 keep theirs and are left exactly as they were.
    #
    #   parent and child, before      ->  parent and child, after
    #   {type: [pages], model: [m1]} @1   {type: [pages]}              @1
    #   {type: [pages], model: [m2]} @2   {type: [pages], model: [m2]} @2
    #   {type: [pages], model: [m3]} @3   {type: [pages], model: [m3]} @3
    #   {type: [pages], model: [m5]} @5   {type: [pages], model: [m5]} @5
    #   {type: [pages]}            @0.5   {type: [pages]}              @0.5
    keep_metric_values(models - %w[m1])

    expect(predicates(ctx[:parent_charge])).to include(m2, m3, m5)
    expect(predicates(ctx[:child_charge])).to eq(predicates(ctx[:parent_charge]))
  end

  # The cascade groups matching filters per child charge. With two charges on the same
  # metric, a mistake there crosses filters between them.
  it "cascades to the edited charge only, leaving the sibling charge untouched" do
    create_plan({
      name: "API Plan", code: "api_plan", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false,
      charges: [
        {billable_metric_id: billable_metric.id, charge_model: "standard", code: "pages_charge",
         properties: {amount: "0.01"}, filters: [model_filter("m1", "1"), model_filter("m2", "2")]},
        {billable_metric_id: billable_metric.id, charge_model: "standard", code: "tokens_charge",
         properties: {amount: "0.02"}, filters: [model_filter("m1", "3"), model_filter("m2", "4")]}
      ]
    })

    parent_plan = organization.plans.find_by(code: "api_plan")
    pages = parent_plan.charges.find_by(code: "pages_charge")
    tokens = parent_plan.charges.find_by(code: "tokens_charge")

    create_subscription({external_customer_id: customer.external_id, external_id: "sub_api", plan_code: "api_plan"})
    subscription = organization.subscriptions.find_by(external_id: "sub_api")
    update_subscription_charge(subscription, "pages_charge", {properties: {amount: "0.01"}})
    subscription.reload

    child_pages = subscription.plan.charges.find_by(code: "pages_charge")
    child_tokens = subscription.plan.charges.find_by(code: "tokens_charge")

    # STEP 1 — the plan drops m2 from pages_charge only, with cascade on.
    #
    #   pages_charge   plan  before: {type: [pages], model: [m1]}  @1
    #                              : {type: [pages], model: [m2]}  @2
    #                        after:  {type: [pages], model: [m1]}  @1
    #                  child before: {type: [pages], model: [m1]}  @1
    #                              : {type: [pages], model: [m2]}  @2
    #                        after:  {type: [pages], model: [m1]}  @1
    #
    #   tokens_charge  plan  before: {type: [pages], model: [m1]}  @3
    #                              : {type: [pages], model: [m2]}  @4
    #                        after:  {type: [pages], model: [m1]}  @3
    #                              : {type: [pages], model: [m2]}  @4
    #                  child before: {type: [pages], model: [m1]}  @3
    #                              : {type: [pages], model: [m2]}  @4
    #                        after:  {type: [pages], model: [m1]}  @3
    #                              : {type: [pages], model: [m2]}  @4
    update_plan(parent_plan, {
      name: "API Plan", code: "api_plan", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false, cascade_updates: true,
      charges: [
        {id: pages.id, billable_metric_id: billable_metric.id, charge_model: "standard",
         properties: {amount: "0.01"}, filters: [model_filter("m1", "1")]},
        {id: tokens.id, billable_metric_id: billable_metric.id, charge_model: "standard",
         properties: {amount: "0.02"}, filters: [model_filter("m1", "3"), model_filter("m2", "4")]}
      ]
    })

    m1 = {"type" => %w[pages], "model" => %w[m1]}

    expect(predicates(pages)).to eq([m1])
    expect(predicates(child_pages)).to eq([m1])
    expect(predicates(tokens)).to eq([m1, m2].sort_by(&:to_s))
    expect(predicates(child_tokens)).to eq([m1, m2].sort_by(&:to_s))
  end

  # Two customers, each with their own override of the same plan. One plan edit has to
  # reach both children: the cascade resolves matching filters per child charge, so a
  # single-override test would never show the second one being skipped.
  it "cascades to every override, not just the first" do
    ctx = setup_plan_with_override
    other = create(:customer, organization:)

    create_subscription({external_customer_id: other.external_id, external_id: "sub_other", plan_code: "api_plan"})
    second = organization.subscriptions.find_by(external_id: "sub_other")
    update_subscription_charge(second, "pages_charge", {properties: {amount: "0.01"}})

    # STEP 1 — the plan drops everything except m5, with cascade on.
    #
    #   before — plan, override A and override B each hold:
    #     {type: [pages], model: [m1]}  @1
    #     {type: [pages], model: [m2]}  @2
    #     {type: [pages], model: [m3]}  @3
    #     {type: [pages], model: [m5]}  @5
    #     {type: [pages]}               @0.5
    #
    #   after — plan, override A and override B each hold:
    #     {type: [pages], model: [m5]}  @5
    update_plan(ctx[:parent_plan], plan_payload(
      [model_filter("m5", "5")], charge_id: ctx[:parent_charge].id, cascade: true
    ))

    expect(predicates(ctx[:parent_charge])).to eq([m5])
    expect(predicates(ctx[:child_charge])).to eq([m5])
    expect(predicates(second.reload.plan.charges.find_by(code: "pages_charge"))).to eq([m5])
  end

  # `to_h` returns the sentinel itself, `to_h_with_all_values` expands it. The cascade
  # matches on `to_h`, so a sentinel filter has to cascade like any other.
  it "cascades a filter using the ALL_FILTER_VALUES sentinel" do
    all_models = {"type" => %w[pages], "model" => [ChargeFilterValue::ALL_FILTER_VALUES]}
    sentinel = {
      invoice_display_name: "Any model", properties: {amount: "7"},
      values: {type: %w[pages], model: [ChargeFilterValue::ALL_FILTER_VALUES]}
    }

    create_plan(plan_payload([sentinel, model_filter("m5", "5")]))
    parent_plan = organization.plans.find_by(code: "api_plan")
    parent_charge = parent_plan.charges.first

    create_subscription({external_customer_id: customer.external_id, external_id: "sub_api", plan_code: "api_plan"})
    subscription = organization.subscriptions.find_by(external_id: "sub_api")
    update_subscription_charge(subscription, "pages_charge", {properties: {amount: "0.01"}})
    child_charge = subscription.reload.plan.charges.first

    expect(predicates(child_charge)).to include(all_models)

    # STEP 1 — the plan drops the sentinel filter and keeps m5, with cascade on.
    #
    #   plan     before: {type: [pages], model: [__ALL_FILTER_VALUES__]}  @7
    #                    {type: [pages], model: [m5]}                     @5
    #            after:  {type: [pages], model: [m5]}                     @5
    #   child    before: {type: [pages], model: [__ALL_FILTER_VALUES__]}  @7
    #                    {type: [pages], model: [m5]}                     @5
    #            after:  {type: [pages], model: [m5]}                     @5
    update_plan(parent_plan, plan_payload(
      [model_filter("m5", "5")], charge_id: parent_charge.id, cascade: true
    ))

    expect(predicates(parent_charge)).to eq([m5])
    expect(predicates(child_charge)).to eq([m5])
  end

  # A full model x region matrix, so every metric edit collapses filters two at a time —
  # once per region — instead of one at a time. Prices encode their origin: the first digit
  # is the model, the second the region (1 = EU, 2 = US), so `21` is {model2, EU}. That
  # makes it readable which row a collapsed predicate came from.
  describe "a model x region matrix" do
    let(:matrix_metric) { create(:sum_billable_metric, organization:, code: "api_calls", field_name: "value") }
    let(:matrix_models) { (1..5).map { "model#{it}" } }

    let(:eu) { {"region" => %w[EU]} }
    let(:us) { {"region" => %w[US]} }

    before do
      create(:billable_metric_filter, billable_metric: matrix_metric, key: "region", values: %w[EU US])
      create(:billable_metric_filter, billable_metric: matrix_metric, key: "model", values: matrix_models)
    end

    def combo(model, region)
      {"region" => [region], "model" => [model]}
    end

    def combo_filter(model, region, amount)
      {
        invoice_display_name: "#{model} #{region}",
        properties: {amount:},
        values: {region: [region], model: [model]}
      }
    end

    def region_filter(region, amount)
      {invoice_display_name: "Any #{region}", properties: {amount:}, values: {region: [region]}}
    end

    def matrix_plan_payload(filters, charge_id: nil, cascade: false)
      charge = {
        billable_metric_id: matrix_metric.id,
        charge_model: "standard",
        code: "calls_charge",
        pay_in_advance: false,
        properties: {amount: "0.01"},
        filters:
      }
      charge[:id] = charge_id if charge_id

      payload = {
        name: "Calls Plan", code: "calls_plan", interval: "monthly", amount_cents: 0,
        amount_currency: "EUR", pay_in_advance: false,
        charges: [charge]
      }
      payload[:cascade_updates] = true if cascade
      payload
    end

    def keep_matrix_models(kept)
      update_metric(matrix_metric, {
        filters: [{key: "region", values: %w[EU US]}, {key: "model", values: kept}]
      })
    end

    def tally(charge)
      charge.filters.reload.map(&:to_h).tally
    end

    def filter_priced(charge, predicate, amount)
      charge.filters.reload.find { it.to_h == predicate && it.properties["amount"] == amount }
    end

    # Every model x region combination priced individually, then overridden for a customer
    def setup_matrix_with_override
      create_plan(matrix_plan_payload(
        matrix_models.each_with_index.flat_map do |model, index|
          [combo_filter(model, "EU", "#{index + 1}1"), combo_filter(model, "US", "#{index + 1}2")]
        end
      ))

      parent_plan = organization.plans.find_by(code: "calls_plan")
      parent_charge = parent_plan.charges.find_by(code: "calls_charge")

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_calls",
        plan_code: "calls_plan"
      })

      subscription = organization.subscriptions.find_by(external_id: "sub_calls")
      update_subscription_charge(subscription, "calls_charge", {properties: {amount: "0.01"}})

      subscription.reload
      {parent_plan:, parent_charge:, subscription:,
       child_charge: subscription.plan.charges.find_by(code: "calls_charge")}
    end

    # Three metric edits, each collapsing one model into both region predicates, then a
    # single plan edit that drops, reprices and adds in one request.
    it "carries the matrix through three metric edits and one plan edit" do
      ctx = setup_matrix_with_override
      parent_charge = ctx[:parent_charge]
      child_charge = ctx[:child_charge]

      # STEP 0 — ten filters, one per combination, deep-copied onto the override.
      #
      #   {region: [EU], model: [model1]} @11   {region: [US], model: [model1]} @12
      #   {region: [EU], model: [model2]} @21   {region: [US], model: [model2]} @22
      #   {region: [EU], model: [model3]} @31   {region: [US], model: [model3]} @32
      #   {region: [EU], model: [model4]} @41   {region: [US], model: [model4]} @42
      #   {region: [EU], model: [model5]} @51   {region: [US], model: [model5]} @52
      expect(tally(parent_charge).values).to all(eq(1))
      expect(tally(parent_charge).size).to eq(10)
      expect(tally(child_charge)).to eq(tally(parent_charge))

      # STEP 1 — metric edit dropping model1 and allowing model6. The two model1 filters
      # lose the `model` key and land on the bare region predicates, keeping their prices.
      # model6 becomes allowed but creates nothing on its own.
      #
      #   {region: [EU], model: [model1]} @11  ->  {region: [EU]} @11
      #   {region: [US], model: [model1]} @12  ->  {region: [US]} @12
      #   everything else unchanged
      keep_matrix_models(matrix_models - %w[model1] + %w[model6])

      expect(tally(parent_charge)[eu]).to eq(1)
      expect(tally(parent_charge)[us]).to eq(1)
      expect(tally(parent_charge).values.sum).to eq(10)
      expect(tally(child_charge)).to eq(tally(parent_charge))

      # STEP 2 — metric edit dropping model2, so a second filter joins each region
      #
      #   {region: [EU], model: [model2]} @21  ->  {region: [EU]} @21
      #   {region: [US], model: [model2]} @22  ->  {region: [US]} @22
      keep_matrix_models(%w[model3 model4 model5 model6])

      expect(tally(parent_charge)[eu]).to eq(2)
      expect(tally(parent_charge)[us]).to eq(2)
      expect(tally(child_charge)).to eq(tally(parent_charge))

      # STEP 3 — metric edit dropping model3, so a third joins each region
      #
      #   {region: [EU], model: [model3]} @31  ->  {region: [EU]} @31
      #   {region: [US], model: [model3]} @32  ->  {region: [US]} @32
      #
      #   {region: [EU]} @11 @21 @31            {region: [US]} @12 @22 @32
      #   {region: [EU], model: [model4]} @41   {region: [US], model: [model4]} @42
      #   {region: [EU], model: [model5]} @51   {region: [US], model: [model5]} @52
      keep_matrix_models(%w[model4 model5 model6])

      expect(tally(parent_charge)[eu]).to eq(3)
      expect(tally(parent_charge)[us]).to eq(3)
      expect(tally(parent_charge).values.sum).to eq(10)
      expect(tally(child_charge)).to eq(tally(parent_charge))

      # STEP 4 — one plan edit stating the end state. A predicate can only be named once
      # in a payload, so the three filters on each region collapse to the one kept here:
      # EU stays at 11, US is repriced to 99, model4 and model5 are untouched, and model6
      # is added for both regions. The cascade is what brings the override in line.
      #
      #   parent and child, before        ->  parent and child, after
      #   {region: [EU]} @11 @21 @31          {region: [EU]} @11
      #   {region: [US]} @12 @22 @32          {region: [US]} @99
      #   {region: [EU], model: [model4]} @41 {region: [EU], model: [model4]} @41
      #   {region: [US], model: [model4]} @42 {region: [US], model: [model4]} @42
      #   {region: [EU], model: [model5]} @51 {region: [EU], model: [model5]} @51
      #   {region: [US], model: [model5]} @52 {region: [US], model: [model5]} @52
      #                                       {region: [EU], model: [model6]} @61  (added)
      #                                       {region: [US], model: [model6]} @62  (added)
      update_plan(ctx[:parent_plan], matrix_plan_payload([
        region_filter("EU", "11"),
        region_filter("US", "99"),
        combo_filter("model4", "EU", "41"),
        combo_filter("model4", "US", "42"),
        combo_filter("model5", "EU", "51"),
        combo_filter("model5", "US", "52"),
        combo_filter("model6", "EU", "61"),
        combo_filter("model6", "US", "62")
      ], charge_id: parent_charge.id, cascade: true))

      expected = {
        eu => 1, us => 1,
        combo("model4", "EU") => 1, combo("model4", "US") => 1,
        combo("model5", "EU") => 1, combo("model5", "US") => 1,
        combo("model6", "EU") => 1, combo("model6", "US") => 1
      }

      expect(tally(parent_charge)).to eq(expected)
      expect(tally(child_charge)).to eq(expected)

      expect(prices_of(parent_charge, us)).to eq(%w[99])
      expect(prices_of(child_charge, us)).to eq(%w[99])
      expect(prices_of(child_charge, eu)).to eq(%w[11])
      expect(prices_of(child_charge, combo("model6", "EU"))).to eq(%w[61])
      expect(prices_of(child_charge, combo("model6", "US"))).to eq(%w[62])
    end

    # The plan-level payload names a predicate once, so it cannot say "drop one of the
    # three filters on {region: [EU]} and keep the other two". The filter endpoints address
    # a filter by id and can. A cascade job only carries a predicate, so each of the three
    # requests below is its own example: they fail independently, and a failure on the
    # delete does not hide what the reprice or the create does.
    #
    # After the three metric edits both sides hold:
    #
    #   {region: [EU]} @11 @21 @31            {region: [US]} @12 @22 @32
    #   {region: [EU], model: [model4]} @41   {region: [US], model: [model4]} @42
    #   {region: [EU], model: [model5]} @51   {region: [US], model: [model5]} @52
    def collapse_to_three_per_region
      ctx = setup_matrix_with_override

      keep_matrix_models(matrix_models - %w[model1] + %w[model6])
      keep_matrix_models(%w[model3 model4 model5 model6])
      keep_matrix_models(%w[model4 model5 model6])

      expect(tally(ctx[:parent_charge])[eu]).to eq(3)
      expect(tally(ctx[:parent_charge])[us]).to eq(3)
      expect(tally(ctx[:child_charge])).to eq(tally(ctx[:parent_charge]))

      ctx
    end

    # Deleting one filter of a collapsed group must leave the other two, on both sides. The job
    # names {region: [EU]}, which all three answer to, so the code is the only thing that tells the
    # cascade which copy the plan actually dropped.
    it "deletes only the targeted filter of a collapsed group" do
      ctx = collapse_to_three_per_region
      parent_charge = ctx[:parent_charge]
      child_charge = ctx[:child_charge]

      # REQUEST 1 — delete the filter that used to be {model3, EU}, the one priced 31.
      #
      #   parent, before: {region: [EU]} @11 @21 @31
      #          after:   {region: [EU]} @11 @21
      #   child,  before: {region: [EU]} @11 @21 @31
      #          after:   {region: [EU]} @11 @21
      delete_plan_charge_filter(
        ctx[:parent_plan], parent_charge.code, filter_priced(parent_charge, eu, "31").id,
        {cascade_updates: true}
      )

      expect(tally(parent_charge)[eu]).to eq(2)
      expect(prices_of(parent_charge, eu).sort).to eq(%w[11 21])

      expect(tally(child_charge)[eu]).to eq(2)
      expect(prices_of(child_charge, eu).sort).to eq(%w[11 21])

      # The US side was not touched by this request
      expect(tally(child_charge)[us]).to eq(3)
    end

    # Repricing one filter of a collapsed group must leave the other two at their own prices. Three
    # filters answer to the predicate and only one of them was repriced, so pairing them by predicate
    # would reprice whichever came back first.
    it "reprices only the targeted filter of a collapsed group" do
      ctx = collapse_to_three_per_region
      parent_charge = ctx[:parent_charge]
      child_charge = ctx[:child_charge]

      # REQUEST 2 — reprice the filter that used to be {model2, US}, priced 22, to 99.
      #
      #   parent, before: {region: [US]} @12 @22 @32
      #          after:   {region: [US]} @12 @99 @32
      #   child,  before: {region: [US]} @12 @22 @32
      #          after:   {region: [US]} @12 @99 @32
      update_plan_charge_filter(
        ctx[:parent_plan], parent_charge.code, filter_priced(parent_charge, us, "22").id,
        {properties: {amount: "99"}, cascade_updates: true}
      )

      expect(tally(parent_charge)[us]).to eq(3)
      expect(prices_of(parent_charge, us).sort).to eq(%w[12 32 99])

      expect(tally(child_charge)[us]).to eq(3)
      expect(prices_of(child_charge, us).sort).to eq(%w[12 32 99])

      # The EU side was not touched by this request
      expect(tally(child_charge)[eu]).to eq(3)
    end

    # model6 was allowed back by the first metric edit, so filters for it can be created.
    # This one does not depend on the collapsed group being handled correctly.
    it "creates filters for a value the metric allowed back" do
      ctx = collapse_to_three_per_region
      parent_charge = ctx[:parent_charge]
      child_charge = ctx[:child_charge]

      # REQUEST 3 and 4
      #
      #   parent and child, after: {region: [EU], model: [model6]} @61
      #                            {region: [US], model: [model6]} @62
      create_plan_charge_filter(ctx[:parent_plan], parent_charge.code,
        combo_filter("model6", "EU", "61").merge(cascade_updates: true))
      create_plan_charge_filter(ctx[:parent_plan], parent_charge.code,
        combo_filter("model6", "US", "62").merge(cascade_updates: true))

      expect(tally(parent_charge)[combo("model6", "EU")]).to eq(1)
      expect(tally(parent_charge)[combo("model6", "US")]).to eq(1)

      expect(tally(child_charge)[combo("model6", "EU")]).to eq(1)
      expect(tally(child_charge)[combo("model6", "US")]).to eq(1)
      expect(prices_of(child_charge, combo("model6", "EU"))).to eq(%w[61])
      expect(prices_of(child_charge, combo("model6", "US"))).to eq(%w[62])

      # Creating a filter must not disturb the collapsed groups
      expect(tally(child_charge)[eu]).to eq(3)
      expect(tally(child_charge)[us]).to eq(3)
    end
  end

  # CascadeService targets children whose plan has an active or pending subscription
  it "does not cascade to an override whose subscription is terminated" do
    ctx = setup_plan_with_override
    child_charge = ctx[:child_charge]

    terminate_subscription(ctx[:subscription])

    # STEP 1 — the plan drops everything except m5, with cascade on. The child plan is
    # left alone because its subscription is no longer active or pending.
    #
    #   plan   before: {type: [pages], model: [m1]}  @1
    #                  {type: [pages], model: [m2]}  @2
    #                  {type: [pages], model: [m3]}  @3
    #                  {type: [pages], model: [m5]}  @5
    #                  {type: [pages]}               @0.5
    #          after:  {type: [pages], model: [m5]}  @5
    #   child  before: the same five filters
    #          after:  the same five filters, untouched
    before_predicates = predicates(child_charge)

    update_plan(ctx[:parent_plan], plan_payload(
      [model_filter("m5", "5")], charge_id: ctx[:parent_charge].id, cascade: true
    ))

    expect(predicates(ctx[:parent_charge])).to eq([m5])
    expect(predicates(child_charge)).to eq(before_predicates)
  end
end
