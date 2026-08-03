# frozen_string_literal: true

require "rails_helper"

# Removing a value from a billable metric filter trims that value out of the charge
# filters referencing it instead of destroying them. Several charge filters can therefore
# end up on the same predicate: `{model: [ocr], type: [pages]}` and
# `{model: [ocr-batch], type: [pages]}` both become `{type: [pages]}` once `model` is gone.
#
# A predicate is what the cascade and the usage calculation key on, so duplicates make both
# ambiguous. These specs pin that one filter survives per predicate, on the plan and on its
# overrides, and that the cascade keeps behaving normally afterwards.
RSpec.describe "Cascade collapsed filter updates", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) do
    create(:sum_billable_metric, organization:, code: "api_pages", field_name: "value")
  end

  let(:models) { %w[ocr-2411 ocr-2512 ocr-2503] }

  let(:pages_predicate) { {"type" => ["pp1k_pages"]} }
  let(:zone_predicate) { {"type" => ["pp1k_pages"], "zone" => ["us"]} }

  before do
    create(:billable_metric_filter, billable_metric:, key: "type", values: %w[pp1k_pages])
    create(:billable_metric_filter, billable_metric:, key: "model", values: models)
    create(:billable_metric_filter, billable_metric:, key: "zone", values: %w[us])
  end

  def model_filter_params
    models.map.with_index do |model, index|
      {
        invoice_display_name: "Model #{index}",
        properties: {amount: (10 * (index + 1)).to_s},
        values: {type: %w[pp1k_pages], model: [model]}
      }
    end
  end

  def zone_filter_params
    {
      invoice_display_name: "US zone",
      properties: {amount: "5"},
      values: {type: %w[pp1k_pages], zone: %w[us]}
    }
  end

  def setup_plan_with_override
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
          filters: model_filter_params + [zone_filter_params]
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

    update_subscription_charge(subscription, "pages_charge", {
      invoice_display_name: "Pages",
      properties: {amount: "0.02"}
    })

    subscription.reload
    child_charge = subscription.plan.charges.find_by(code: "pages_charge")
    child_charge.filters.each { it.update!(properties: {"amount" => "9"}) }

    {parent_plan:, parent_charge:, child_charge:, subscription:}
  end

  def remove_model_key
    update_metric(billable_metric, {
      filters: [
        {key: "type", values: %w[pp1k_pages]},
        {key: "zone", values: %w[us]}
      ]
    })
  end

  def remove_first_model_value
    update_metric(billable_metric, {
      filters: [
        {key: "type", values: %w[pp1k_pages]},
        {key: "model", values: models.drop(1)},
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

  def predicates(charge)
    charge.filters.reload.map(&:to_h)
  end

  it "keeps one filter per predicate on the plan and on the override" do
    ctx = setup_plan_with_override

    expect(predicates(ctx[:parent_charge]).size).to eq(4)

    remove_model_key

    expect(predicates(ctx[:parent_charge])).to contain_exactly(pages_predicate, zone_predicate)
    expect(predicates(ctx[:child_charge])).to contain_exactly(pages_predicate, zone_predicate)
  end

  it "leaves untouched filters alone when a single value is removed" do
    ctx = setup_plan_with_override

    remove_first_model_value

    expect(predicates(ctx[:parent_charge])).to contain_exactly(
      pages_predicate,
      {"type" => ["pp1k_pages"], "model" => ["ocr-2512"]},
      {"type" => ["pp1k_pages"], "model" => ["ocr-2503"]},
      zone_predicate
    )
    expect(predicates(ctx[:child_charge])).to eq(predicates(ctx[:parent_charge]))
  end

  it "preserves the negotiated override price of the surviving filter" do
    ctx = setup_plan_with_override

    remove_model_key

    surviving = ctx[:child_charge].filters.reload.find { it.to_h == pages_predicate }
    expect(surviving.properties).to eq({"amount" => "9"})
  end

  it "cascades the deletion of a collapsed filter to the override" do
    ctx = setup_plan_with_override
    remove_model_key

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [zone_filter_params])

    expect(predicates(ctx[:parent_charge])).to contain_exactly(zone_predicate)
    expect(predicates(ctx[:child_charge])).to contain_exactly(zone_predicate)
  end

  it "enqueues one destroy job for the collapsed predicate" do
    ctx = setup_plan_with_override
    remove_model_key

    payloads = []
    allow(ChargeFilters::CascadeJob).to receive(:perform_later).and_wrap_original do |original, *args|
      payloads << {action: args[1], values: args[2]}
      original.call(*args)
    end

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [zone_filter_params])

    destroys = payloads.select { it[:action] == "destroy" }
    expect(destroys.map { it[:values] }).to eq([pages_predicate])
  end

  it "bills the override at the charge default once the filter is gone" do
    ctx = setup_plan_with_override
    remove_model_key
    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], [zone_filter_params])

    create_event({
      code: billable_metric.code,
      external_subscription_id: "sub_api",
      properties: {value: "10", type: "pp1k_pages"}
    })

    fetch_current_usage(customer:, subscription: ctx[:subscription])

    customer_usage = json[:customer_usage]
    expect(customer_usage[:charges_usage].first[:units]).to eq("10.0")
    expect(customer_usage[:amount_cents]).to eq(20)
  end

  it "cascades an ordinary price change without removing filters" do
    ctx = setup_plan_with_override

    repriced = model_filter_params
    repriced.first[:properties] = {amount: "99"}

    update_parent_filters(ctx[:parent_plan], ctx[:parent_charge], repriced + [zone_filter_params])

    expect(predicates(ctx[:parent_charge]).size).to eq(4)
    expect(predicates(ctx[:child_charge]).size).to eq(4)
  end
end
