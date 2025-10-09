# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::BillableMetricResolver do
  subject(:graphql_request) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {billableMetricId: billable_metric.id}
    )
  end

  let(:required_permission) { "billable_metrics:view" }
  let(:query) do
    <<~GQL
      query($billableMetricId: ID!) {
        billableMetric(id: $billableMetricId) {
          id
          name
          hasSubscriptions
          hasActiveSubscriptions
          hasDraftInvoices
          hasPlans
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "billable_metrics:view"

  it "returns a single billable metric" do
    metric_response = graphql_request["data"]["billableMetric"]

    expect(metric_response["id"]).to eq(billable_metric.id)
    expect(metric_response["hasSubscriptions"]).to eq(false)
    expect(metric_response["hasActiveSubscriptions"]).to eq(false)
    expect(metric_response["hasDraftInvoices"]).to eq(false)
    expect(metric_response["hasPlans"]).to eq(false)
  end

  context "when billable metric has subscriptions" do
    before do
      terminated_subscription = create(:subscription, :terminated)
      create(:standard_charge, plan: terminated_subscription.plan, billable_metric:)
    end

    it "returns true for has subscriptions" do
      metric_response = graphql_request["data"]["billableMetric"]
      expect(metric_response["hasSubscriptions"]).to eq(true)
      expect(metric_response["hasActiveSubscriptions"]).to eq(false)
    end
  end

  context "when billable metric has active subscriptions" do
    before do
      terminated_subscription = create(:subscription, :terminated)
      create(:standard_charge, plan: terminated_subscription.plan, billable_metric:)

      subscription = create(:subscription)
      create(:standard_charge, plan: subscription.plan, billable_metric:)
    end

    it "returns true for has active subscriptions" do
      metric_response = graphql_request["data"]["billableMetric"]
      expect(metric_response["hasSubscriptions"]).to eq(true)
      expect(metric_response["hasActiveSubscriptions"]).to eq(true)
    end
  end

  context "when billable metric has draft invoices" do
    before do
      customer = create(:customer, organization: billable_metric.organization)
      subscription = create(:subscription)
      subscription_2 = create(:subscription)
      charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
      charge_2 = create(:standard_charge, plan: subscription_2.plan, billable_metric:)

      invoice = create(:invoice, customer:, organization: billable_metric.organization)
      create(:fee, invoice:, charge:)

      draft_invoice = create(:invoice, :draft, customer:, organization: billable_metric.organization)
      create(:fee, invoice: draft_invoice, charge: charge_2)
      create(:fee, invoice: draft_invoice, charge: charge_2)
    end

    it "returns true for has draft invoices" do
      metric_response = graphql_request["data"]["billableMetric"]
      expect(metric_response["hasDraftInvoices"]).to eq(true)
    end
  end

  context "when billable metric has plans" do
    before do
      subscription = create(:subscription)
      subscription_2 = create(:subscription)
      create(:standard_charge, plan: subscription.plan, billable_metric:)
      create(:standard_charge, plan: subscription_2.plan, billable_metric:)
    end

    it "returns true for has plans" do
      metric_response = graphql_request["data"]["billableMetric"]
      expect(metric_response["hasPlans"]).to eq(true)
    end
  end

  context "when billable metric is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
