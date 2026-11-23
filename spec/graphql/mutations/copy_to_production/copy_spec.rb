# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CopyToProduction::Copy do
  subject(:execution) do
    execute_graphql(
      current_user: user,
      current_organization: sandbox,
      permissions: required_permission,
      query: mutation,
      variables: {input: {itemType: "billable_metric", id: metric.id}}
    )
  end

  include_context "with self-serve enabled"

  let(:required_permission) { "copy_to_production:create" }
  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:user) { create(:user) }
  let(:membership) { create(:membership, user:, organization: sandbox, roles: %i[admin]) }
  let(:production_roles) { %i[admin] }
  let(:metric) { create(:billable_metric, organization: sandbox, code: "api_calls", name: "API calls") }

  let(:mutation) do
    <<~GQL
      mutation($input: CopyToProductionInput!) {
        copyToProduction(input: $input) { id itemType code name }
      }
    GQL
  end

  before do
    create(:membership, user:, organization: production, roles: production_roles)
    create(:billable_metric_filter, billable_metric: metric, key: "region", values: %w[eu us])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "copy_to_production:create"

  it_behaves_like "a self-serve entry point" do
    let(:result) { execution }
  end

  it "copies the billable metric to production" do
    data = execution["data"]["copyToProduction"]
    copy = production.billable_metrics.find_by(code: "api_calls")

    expect(data).to eq("id" => copy.id, "itemType" => "billable_metric", "code" => "api_calls", "name" => "API calls")
    expect(copy.filters.pluck(:key, :values)).to eq([["region", %w[eu us]]])
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "returns a validation error" do
      expect_unprocessable_entity(execution, details: {code: ["value_already_exist"]})
    end
  end

  context "when the item's parent is not live" do
    let(:parent) { create(:billable_metric, organization: sandbox, code: "parent_metric") }
    let(:service_result) do
      CopyToProduction::CopyService::Result.new.tap do |result|
        result.missing_parent = CopyToProduction::CopyService::Entry.new(item_type: "billable_metric", record: parent)
        result.forbidden_failure!(code: "copy_to_production_parent_missing")
      end
    end

    before { allow(CopyToProduction::CopyService).to receive(:call).and_return(service_result) }

    it "returns a forbidden error naming the parent" do
      error = execution["errors"].first

      expect(error["extensions"]).to eq(
        "status" => 403,
        "code" => "copy_to_production_parent_missing",
        "details" => {"itemType" => "billable_metric", "code" => "parent_metric"}
      )
    end
  end

  context "when the user is not an admin of production" do
    let(:production_roles) { %i[finance] }

    it "returns a forbidden error" do
      expect_graphql_error(result: execution, message: "copy_to_production_admin_only")
      expect(production.billable_metrics).to be_empty
    end
  end

  context "with a feature" do
    subject(:execution) do
      execute_graphql(
        current_user: user,
        current_organization: sandbox,
        permissions: required_permission,
        query: mutation,
        variables: {input: {itemType: "feature", id: feature.id}}
      )
    end

    let(:feature) { create(:feature, organization: sandbox, code: "seats", name: "Seats") }

    before { create(:privilege, feature:, code: "max", value_type: "integer") }

    it "copies the feature to production" do
      data = execution["data"]["copyToProduction"]
      copy = production.features.find_by(code: "seats")

      expect(data).to eq("id" => copy.id, "itemType" => "feature", "code" => "seats", "name" => "Seats")
      expect(copy.privileges.pluck(:code, :value_type)).to eq([["max", "integer"]])
    end
  end
end
