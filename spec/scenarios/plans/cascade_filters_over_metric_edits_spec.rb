# frozen_string_literal: true

require "rails_helper"

# Walks a plan and its override through metric edits and plan edits, checking both sides
# after every step. Each step lists the filters before and after, written out in full as
# `{key: [values]} @price`, so the state is readable without running anything.
#
# Three things are pinned here:
#   - filters left on a shared predicate by a metric edit are NOT deleted for the customer
#   - a price negotiated on the override is NOT overwritten by a plan reprice
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
