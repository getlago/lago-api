# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Billing::EnrollService, :premium do
  subject(:result) { described_class.call(storefront:, registration:, plan_code:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:plan_code) { plan.code }

  before { storefront.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}]) }

  it "creates the customer, the subscription and an empty wallet" do
    expect(result).to be_success

    customer = organization.customers.sole
    expect(customer).to have_attributes(
      external_id: "agent_#{registration.id}",
      name: "Agent · #{registration.id}",
      exclude_from_dunning_campaign: true
    )
    expect(result.subscription).to have_attributes(
      customer:, plan:, external_id: "agent_#{registration.id}", billing_time: "calendar", status: "active"
    )
    expect(result.wallet).to have_attributes(
      customer:, code: "agent_credits", currency: "USD", rate_amount: 1, balance_cents: 0,
      paid_top_up_min_amount_cents: 500, paid_top_up_max_amount_cents: 10_000
    )
  end

  it "returns the same records when called again" do
    first = described_class.call(storefront:, registration:, plan_code:)

    expect(result.subscription).to eq(first.subscription)
    expect(result.wallet).to eq(first.wallet)
    expect(organization.customers.count).to eq(1)
  end

  context "when the merchant overrode the plan of the agent's subscription" do
    let(:first) { described_class.call(storefront:, registration:, plan_code:) }

    before { first.subscription.update!(plan: create(:plan, organization:, parent: plan, code: plan.code, amount_cents: 0)) }

    it "still returns the same records" do
      expect(result).to be_success
      expect(result.subscription).to eq(first.subscription)
    end
  end

  context "when the registration is enrolled in another plan" do
    let(:other_plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }

    before do
      storefront.update!(plans: storefront.plans + [{plan_code: other_plan.code}])
      described_class.call(storefront:, registration:, plan_code: other_plan.code)
    end

    it "refuses" do
      expect(result).to be_failure
      expect(result.error.code).to eq("already_enrolled")
    end
  end

  context "with a plan the storefront does not sell" do
    let(:plan_code) { create(:plan, organization:, amount_cents: 0).code }

    it "refuses" do
      expect(result.error.messages).to eq(plan_code: ["plan_not_sold"])
    end
  end

  context "with a plan that has a subscription fee" do
    let(:plan) { create(:plan, organization:, amount_cents: 2_000, amount_currency: "USD") }

    it "refuses without creating anything" do
      expect(result.error.messages).to eq(plan_code: ["plan_not_usage_only"])
      expect(organization.customers).to be_empty
    end
  end
end
