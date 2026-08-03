# frozen_string_literal: true

require "rails_helper"

# Editing a billable metric filter does not destroy the charge filters that reference
# the removed values: it strips those values out. Several charge filters can therefore
# collapse onto one identical predicate (e.g. six `{model: [...], type: [pp1k_pages]}`
# filters all become `{type: [pp1k_pages]}`).
#
# The cascade diff keys filters by their `values` payload, so a collapsed predicate
# resolves to a *group* of rows rather than a single one. These specs pin the behaviour
# for that group: every duplicate must be reconciled on the child override, and the
# child must never keep a stale filter that bills at a rate the parent no longer has.
RSpec.describe "Cascade collapsed filter updates", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) do
    create(:sum_billable_metric, organization:, code: "api_pages", field_name: "value")
  end

  let(:models) { %w[ocr-2411 ocr-2512 ocr-2503 ocr-4 ocr-2505 ocr-4-launch] }

  before do
    create(:billable_metric_filter, billable_metric:, key: "type", values: %w[pp1k_pages])
    create(:billable_metric_filter, billable_metric:, key: "model", values: models)
    create(:billable_metric_filter, billable_metric:, key: "zone", values: %w[us])
  end

  # Parent charge: one filter per model (all sharing type: pp1k_pages) plus a zone
  # filter that never collapses. The child override mirrors the shape at its own rates.
  def setup_plan_with_override
    model_filters = models.map.with_index do |model, index|
      {
        invoice_display_name: "Model #{index}",
        properties: {amount: "10"},
        values: {type: %w[pp1k_pages], model: [model]}
      }
    end
    zone_filter = {
      invoice_display_name: "US zone",
      properties: {amount: "5"},
      values: {type: %w[pp1k_pages], zone: %w[us]}
    }

    create_plan({
      name: "API Plan",
      code: "api_plan",
      interval: "monthly",
      amount_cents: 0,
      amount_currency: "EUR",
      pay_in_advance: false,
      charges: [
        {
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          code: "pages_charge",
          pay_in_advance: false,
          properties: {amount: "0.01"},
          filters: model_filters + [zone_filter]
        }
      ]
    })

    parent_plan = organization.plans.find_by(code: "api_plan")
    parent_charge = parent_plan.charges.find_by(code: "pages_charge")

    create_subscription({
      external_customer_id: customer.external_id,
      external_id: "sub_api",
      plan_code: "api_plan"
    })

    subscription = organization.subscriptions.find_by(external_id: "sub_api")

    # Negotiated child rates: the override keeps its own prices on every filter.
    update_subscription_charge(subscription, "pages_charge", {
      invoice_display_name: "Pages",
      properties: {amount: "0.02"}
    })

    subscription.reload
    child_charge = subscription.plan.charges.find_by(code: "pages_charge")
    child_charge.filters.each do |filter|
      filter.update!(properties: {"amount" => filter.to_h.key?("zone") ? "4" : "9"})
    end

    {parent_plan:, parent_charge:, child_charge:, subscription:}
  end

  # Drops the whole `model` key, collapsing every model filter onto {type: [pp1k_pages]}.
  def collapse_model_key
    update_metric(billable_metric, {
      filters: [
        {key: "type", values: %w[pp1k_pages]},
        {key: "zone", values: %w[us]}
      ]
    })
  end

  def update_parent_filters(parent_plan, parent_charge, filters)
    update_plan(parent_plan, {
      name: "API Plan",
      code: "api_plan",
      interval: "monthly",
      amount_cents: 0,
      amount_currency: "EUR",
      cascade_updates: true,
      charges: [
        {
          id: parent_charge.id,
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          properties: {amount: "0.01"},
          filters:
        }
      ]
    })
  end

  def predicate_counts(charge)
    charge.filters.reload.map(&:to_h).tally
  end

  let(:collapsed_predicate) { {"type" => ["pp1k_pages"]} }
  let(:zone_predicate) { {"type" => ["pp1k_pages"], "zone" => ["us"]} }

  it "collapses several charge filters onto one predicate when a metric key is removed" do
    ctx = setup_plan_with_override

    expect(predicate_counts(ctx[:parent_charge])).to eq(
      {"type" => ["pp1k_pages"], "model" => ["ocr-2411"]} => 1,
      {"type" => ["pp1k_pages"], "model" => ["ocr-2512"]} => 1,
      {"type" => ["pp1k_pages"], "model" => ["ocr-2503"]} => 1,
      {"type" => ["pp1k_pages"], "model" => ["ocr-4"]} => 1,
      {"type" => ["pp1k_pages"], "model" => ["ocr-2505"]} => 1,
      {"type" => ["pp1k_pages"], "model" => ["ocr-4-launch"]} => 1,
      zone_predicate => 1
    )

    collapse_model_key

    # The six model filters now share one predicate on the parent *and* on the override.
    expect(predicate_counts(ctx[:parent_charge])).to eq(collapsed_predicate => 6, zone_predicate => 1)
    expect(predicate_counts(ctx[:child_charge])).to eq(collapsed_predicate => 6, zone_predicate => 1)
  end

  it "removes every collapsed duplicate from the override when the parent drops them all" do
    ctx = setup_plan_with_override
    collapse_model_key

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    # Parent kept only the zone filter, and the override must match: no stale
    # {type: [pp1k_pages]} row may survive, otherwise it keeps billing at "9".
    expect(predicate_counts(ctx[:parent_charge])).to eq(zone_predicate => 1)
    expect(predicate_counts(ctx[:child_charge])).to eq(zone_predicate => 1)
  end

  # Regression: the diff deletes the whole group for a predicate found in `after`.
  # Comparing only a single representative made this look like a no-op, so no job was
  # enqueued, the parent self-healed to one row and the override silently kept all six.
  it "converges the override to a single row when the parent keeps one collapsed filter" do
    ctx = setup_plan_with_override
    collapse_model_key

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [
      {
        invoice_display_name: "Pages",
        properties: {amount: "10"},
        values: {type: %w[pp1k_pages]}
      },
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    expect(predicate_counts(ctx[:parent_charge])).to eq(collapsed_predicate => 1, zone_predicate => 1)
    expect(predicate_counts(ctx[:child_charge])).to eq(collapsed_predicate => 1, zone_predicate => 1)
  end

  it "preserves the negotiated override price while deduplicating" do
    ctx = setup_plan_with_override
    collapse_model_key

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [
      {
        invoice_display_name: "Pages",
        properties: {amount: "10"},
        values: {type: %w[pp1k_pages]}
      },
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    surviving = ctx[:child_charge].filters.reload.find { |f| f.to_h == collapsed_predicate }

    # Deduplication must not clobber a customized child price.
    expect(surviving.properties).to eq({"amount" => "9"})
  end

  it "emits a single destroy job for a collapsed predicate" do
    ctx = setup_plan_with_override
    collapse_model_key

    payloads = []
    allow(ChargeFilters::CascadeJob).to receive(:perform_later).and_wrap_original do |original, *args|
      payloads << {action: args[1], values: args[2]}
      original.call(*args)
    end

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    # One job per predicate, not per duplicated row: CascadeService fans that single
    # destroy out to every matching filter on each child charge.
    destroys = payloads.select { |p| p[:action] == "destroy" }
    expect(destroys.size).to eq(1)
    expect(destroys.first[:values]).to eq(collapsed_predicate)
  end

  it "does not bill the override at a rate the parent no longer has" do
    ctx = setup_plan_with_override
    collapse_model_key

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    # No stale row survives on the override, so nothing can bill at the old "9" rate.
    expect(ctx[:child_charge].filters.reload.map(&:to_h)).not_to include(collapsed_predicate)

    create_event({
      code: billable_metric.code,
      external_subscription_id: "sub_api",
      properties: {value: "10", type: "pp1k_pages"}
    })

    fetch_current_usage(customer:, subscription: ctx[:subscription])

    customer_usage = json[:customer_usage]
    charge_usage = customer_usage[:charges_usage].first

    # 10 units fall back to the charge default (0.02 EUR) = 20 cents. A surviving
    # duplicate would have priced them at 9 EUR/unit instead.
    expect(charge_usage[:units]).to eq("10.0")
    expect(customer_usage[:amount_cents]).to eq(20)
  end

  # Guard against over-correcting: an ordinary, non-collapsed update must still
  # cascade exactly one row and must not delete anything.
  it "still cascades an ordinary filter update without duplicates" do
    ctx = setup_plan_with_override

    model_filters = models.map.with_index do |model, index|
      amount = (index.zero?) ? "12" : "10"
      {
        invoice_display_name: "Model #{index}",
        properties: {amount:},
        values: {type: %w[pp1k_pages], model: [model]}
      }
    end

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], model_filters + [
      {
        invoice_display_name: "US zone",
        properties: {amount: "5"},
        values: {type: %w[pp1k_pages], zone: %w[us]}
      }
    ])

    expect(ctx[:child_charge].filters.reload.count).to eq(7)

    # The child had customized every filter, so its price is preserved; the point is
    # that no row was destroyed and the predicate set is untouched.
    expect(predicate_counts(ctx[:child_charge]).values.uniq).to eq([1])
  end
end
