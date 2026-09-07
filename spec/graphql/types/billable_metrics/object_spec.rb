# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::BillableMetrics::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization")
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:description).of_type("String")
    expect(subject).to have_field(:aggregation_type).of_type("AggregationTypeEnum!")
    expect(subject).to have_field(:expression).of_type("String")
    expect(subject).to have_field(:field_name).of_type("String")
    expect(subject).to have_field(:weighted_interval).of_type("WeightedIntervalEnum")
    expect(subject).to have_field(:filters).of_type("[BillableMetricFilter!]")
    expect(subject).to have_field(:recurring).of_type("Boolean!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:deleted_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:integration_mappings).of_type("[Mapping!]")
    expect(subject).to have_field(:rounding_function).of_type("RoundingFunctionEnum")
    expect(subject).to have_field(:rounding_precision).of_type("Int")
    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")

    expect(subject).to have_field(:has_active_subscriptions).of_type("Boolean!")
    expect(subject).to have_field(:has_draft_invoices).of_type("Boolean!")
    expect(subject).to have_field(:has_plans).of_type("Boolean!")
    expect(subject).to have_field(:has_subscriptions).of_type("Boolean!")
  end

  describe "#has_subscriptions" do
    let(:required_permission) { "billable_metrics:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:query) do
      <<~GQL
        query($billableMetricId: ID!) {
          billableMetric(id: $billableMetricId) { hasSubscriptions }
        }
      GQL
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: billable_metric.id}
      ).dig("data", "billableMetric", "hasSubscriptions")
    end

    context "when the billable metric has subscriptions" do
      before do
        plan = create(:plan, organization:)
        create(:subscription, :terminated, plan:, organization:)
        create(:standard_charge, plan:, billable_metric:, organization:)
      end

      it "returns true" do
        expect(execute).to eq(true)
      end
    end

    context "when the billable metric has no subscriptions" do
      it "returns false" do
        expect(execute).to eq(false)
      end
    end
  end

  describe "#has_active_subscriptions" do
    let(:required_permission) { "billable_metrics:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:query) do
      <<~GQL
        query($billableMetricId: ID!) {
          billableMetric(id: $billableMetricId) { hasActiveSubscriptions }
        }
      GQL
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: billable_metric.id}
      ).dig("data", "billableMetric", "hasActiveSubscriptions")
    end

    context "when the billable metric only has terminated subscriptions" do
      before do
        plan = create(:plan, organization:)
        create(:subscription, :terminated, plan:, organization:)
        create(:standard_charge, plan:, billable_metric:, organization:)
      end

      it "returns false" do
        expect(execute).to eq(false)
      end
    end

    context "when the billable metric has an active subscription" do
      before do
        terminated_plan = create(:plan, organization:)
        create(:subscription, :terminated, plan: terminated_plan, organization:)
        create(:standard_charge, plan: terminated_plan, billable_metric:, organization:)

        active_plan = create(:plan, organization:)
        create(:subscription, plan: active_plan, organization:)
        create(:standard_charge, plan: active_plan, billable_metric:, organization:)
      end

      it "returns true" do
        expect(execute).to eq(true)
      end
    end
  end

  describe "#has_draft_invoices" do
    let(:required_permission) { "billable_metrics:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:query) do
      <<~GQL
        query($billableMetricId: ID!) {
          billableMetric(id: $billableMetricId) { hasDraftInvoices }
        }
      GQL
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: billable_metric.id}
      ).dig("data", "billableMetric", "hasDraftInvoices")
    end

    context "when a draft invoice has a fee on one of the metric's charges" do
      before do
        customer = create(:customer, organization:)
        plan = create(:plan, organization:)
        plan_2 = create(:plan, organization:)
        create(:subscription, plan:, organization:)
        create(:subscription, plan: plan_2, organization:)
        charge = create(:standard_charge, plan:, billable_metric:, organization:)
        charge_2 = create(:standard_charge, plan: plan_2, billable_metric:, organization:)

        invoice = create(:invoice, customer:, organization:)
        create(:fee, invoice:, charge:)

        draft_invoice = create(:invoice, :draft, customer:, organization:)
        create(:fee, invoice: draft_invoice, charge: charge_2)
        create(:fee, invoice: draft_invoice, charge: charge_2)
      end

      it "returns true" do
        expect(execute).to eq(true)
      end
    end

    context "when the billable metric only has finalized invoices" do
      before do
        customer = create(:customer, organization:)
        plan = create(:plan, organization:)
        create(:subscription, plan:, organization:)
        charge = create(:standard_charge, plan:, billable_metric:, organization:)

        invoice = create(:invoice, customer:, organization:, status: :finalized)
        create(:fee, invoice:, charge:)
      end

      it "returns false" do
        expect(execute).to eq(false)
      end
    end

    context "when the billable metric has no invoices" do
      it "returns false" do
        expect(execute).to eq(false)
      end
    end
  end

  describe "#has_plans" do
    let(:required_permission) { "billable_metrics:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:query) do
      <<~GQL
        query($billableMetricId: ID!) {
          billableMetric(id: $billableMetricId) { hasPlans }
        }
      GQL
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: billable_metric.id}
      ).dig("data", "billableMetric", "hasPlans")
    end

    context "when a charge attaches the billable metric to a plan" do
      before do
        plan = create(:plan, organization:)
        plan_2 = create(:plan, organization:)
        create(:subscription, plan:, organization:)
        create(:subscription, plan: plan_2, organization:)
        create(:standard_charge, plan:, billable_metric:, organization:)
        create(:standard_charge, plan: plan_2, billable_metric:, organization:)
      end

      it "returns true" do
        expect(execute).to eq(true)
      end
    end

    context "when the billable metric is not attached to any plan" do
      it "returns false" do
        expect(execute).to eq(false)
      end
    end
  end

  describe "#integration_mappings" do
    let(:required_permission) { "billable_metrics:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:netsuite_integration) { create(:netsuite_integration, organization:) }
    let(:xero_integration) { create(:xero_integration, organization:) }
    let(:netsuite_mapping) { create(:netsuite_mapping, integration: netsuite_integration, mappable: billable_metric, organization:) }
    let(:xero_mapping) { create(:xero_mapping, integration: xero_integration, mappable: billable_metric, organization:) }
    let(:integration_id) { nil }

    let(:query) do
      <<~GQL
        query($billableMetricId: ID!, $integrationId: ID) {
          billableMetric(id: $billableMetricId) {
            integrationMappings(integrationId: $integrationId) { id }
          }
        }
      GQL
    end

    before do
      netsuite_mapping
      xero_mapping
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: billable_metric.id, integrationId: integration_id}
      ).dig("data", "billableMetric", "integrationMappings")
    end

    context "without the integrationId argument" do
      it "returns all the mappings of the billable metric" do
        expect(execute.map { |mapping| mapping["id"] }).to match_array([netsuite_mapping.id, xero_mapping.id])
      end
    end

    context "with the integrationId argument" do
      let(:integration_id) { netsuite_integration.id }

      it "returns only the mappings of the given integration" do
        expect(execute.map { |mapping| mapping["id"] }).to eq([netsuite_mapping.id])
      end
    end
  end
end
