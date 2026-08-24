# frozen_string_literal: true

require "rails_helper"

RSpec.describe "v1 pricing endpoints on a product-catalog organization", type: :request do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }

  it "rejects legacy pricing fields on plan creation" do
    post_with_token(organization, "/api/v1/plans", {plan: {name: "Legacy", code: "legacy", interval: "monthly", amount_cents: 100, amount_currency: "USD", pay_in_advance: false}})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq({interval: %w[legacy_billing_disabled]})
  end

  it "creates a catalog plan from a payload without legacy pricing fields" do
    post_with_token(organization, "/api/v1/plans", {plan: {name: "Catalog", code: "catalog", amount_currency: "USD"}})

    expect(response).to have_http_status(:success)
    expect(json[:plan][:code]).to eq("catalog")
  end

  it "tolerates blank legacy no-ops without persisting them" do
    post_with_token(organization, "/api/v1/plans", {plan: {name: "Catalog", code: "catalog_blank", amount_currency: "USD", pay_in_advance: false, interval: ""}})

    expect(response).to have_http_status(:success)
    expect(organization.plans.find_by(code: "catalog_blank")).to have_attributes(pricing_type: "product_catalog", interval: nil)
  end

  it "rejects legacy pricing fields on plan update but accepts the others" do
    put_with_token(organization, "/api/v1/plans/#{plan.code}", {plan: {amount_cents: 100}})
    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq({amount_cents: %w[legacy_billing_disabled]})

    put_with_token(organization, "/api/v1/plans/#{plan.code}", {plan: {name: "Renamed"}})
    expect(response).to have_http_status(:success)
    expect(json[:plan][:name]).to eq("Renamed")
  end

  it "allows deleting a catalog plan" do
    delete_with_token(organization, "/api/v1/plans/#{plan.code}")

    expect(response).to have_http_status(:success)
  end

  it "rejects plan overrides on subscriptions", :premium do
    customer = create(:customer, organization:)
    legacy_plan = create(:plan, organization:)

    post_with_token(organization, "/api/v1/subscriptions", {subscription: {external_customer_id: customer.external_id, external_id: "sub_ovr", plan_code: legacy_plan.code, plan_overrides: {amount_cents: 5000}}})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq({plan_overrides: %w[legacy_billing_disabled]})
  end

  it "hides legacy plans from the v2 catalog surface" do
    legacy_plan = create(:plan, organization:)

    get_with_token(organization, "/api/v2/plans/#{legacy_plan.code}")
    expect(response).to be_not_found_error("plan")

    put_with_token(organization, "/api/v2/plans/#{legacy_plan.code}", {plan: {name: "x"}})
    expect(response).to be_not_found_error("plan")
  end

  it "rejects nested charges on a pre-migration legacy plan" do
    legacy_plan = create(:plan, organization:)
    metric = create(:billable_metric, organization:)

    put_with_token(organization, "/api/v1/plans/#{legacy_plan.code}", {plan: {charges: [{billable_metric_id: metric.id, charge_model: "standard", properties: {amount: "0.10"}}]}})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq({charges: %w[legacy_billing_disabled]})
  end

  it "forbids adding a v1 charge to a plan" do
    metric = create(:billable_metric, organization:)
    post_with_token(organization, "/api/v1/plans/#{plan.code}/charges", {charge: {billable_metric_id: metric.id, charge_model: "standard", properties: {amount: "0.10"}}})

    expect(response).to have_http_status(:forbidden)
    expect(json[:code]).to eq("legacy_billing_disabled")
  end

  it "forbids adding a v1 fixed charge to a plan" do
    add_on = create(:add_on, organization:)
    post_with_token(organization, "/api/v1/plans/#{plan.code}/fixed_charges", {fixed_charge: {add_on_id: add_on.id, charge_model: "standard", units: 1, properties: {amount: "10"}}})

    expect(response).to have_http_status(:forbidden)
    expect(json[:code]).to eq("legacy_billing_disabled")
  end

  it "keeps v1 reads open" do
    get_with_token(organization, "/api/v1/plans")

    expect(response).to have_http_status(:success)
  end

  it "forbids the subscription-side write endpoints and keeps their reads open" do
    customer = create(:customer, organization:)
    legacy_plan = create(:plan, organization:)
    subscription = create(:subscription, organization:, customer:, plan: legacy_plan, external_id: "sub_gate")
    charge = create(:standard_charge, organization:, plan: legacy_plan)

    get_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}/charges")
    expect(response).to have_http_status(:success)

    put_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}/charges/#{charge.code}", {charge: {invoice_display_name: "x"}})
    expect(response).to have_http_status(:forbidden)
    expect(json[:code]).to eq("legacy_billing_disabled")
  end
end
