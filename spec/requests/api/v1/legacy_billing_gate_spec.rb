# frozen_string_literal: true

require "rails_helper"

RSpec.describe "v1 pricing endpoints on a product-catalog organization", type: :request do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }

  it "forbids creating a v1 plan" do
    post_with_token(organization, "/api/v1/plans", {plan: {name: "Legacy", code: "legacy", interval: "monthly", amount_cents: 100, amount_currency: "USD", pay_in_advance: false}})

    expect(response).to have_http_status(:forbidden)
    expect(json[:code]).to eq("legacy_billing_disabled")
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
