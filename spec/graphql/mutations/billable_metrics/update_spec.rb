# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::BillableMetrics::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:billable_metric) { create(:weighted_sum_billable_metric, organization: membership.organization) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateBillableMetricInput!) {
        updateBillableMetric(input: $input) {
          id,
          name,
          code,
          aggregationType,
          weightedInterval
          recurring
          organization { id },
          group
        }
      }
    GQL
  end

  it "updates a billable metric" do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: billable_metric.id,
          name: "New Metric",
          code: "new_metric",
          description: "New metric description",
          aggregationType: "count_agg",
          recurring: false,
          weightedInterval: "seconds"
        }
      }
    )

    result_data = result["data"]["updateBillableMetric"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["name"]).to eq("New Metric")
      expect(result_data["code"]).to eq("new_metric")
      expect(result_data["organization"]["id"]).to eq(membership.organization_id)
      expect(result_data["aggregationType"]).to eq("count_agg")
      expect(result_data["weightedInterval"]).to eq("seconds")
      expect(result_data["recurring"]).to eq(false)
    end
  end

  context "with group parameter" do
    let(:group) do
      {
        key: "cloud",
        values: [
          {name: "AWS", key: "region", values: %w[usa europe]},
          {name: "Google", key: "region", values: ["usa"]}
        ]
      }
    end

    it "updates billable metric's group" do
      create(:group, billable_metric:)

      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: billable_metric.id,
            name: "metric",
            code: "metric",
            description: "metric description",
            aggregationType: "count_agg",
            group:
          }
        }
      )
      result_data = result["data"]["updateBillableMetric"]

      expect(result_data["group"]).to eq(group)
    end
  end

  context "with invalid group parameter" do
    let(:group) do
      {key: "foo", foo: "bar"}
    end

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: billable_metric.id,
            name: "metric",
            code: "metric",
            description: "metric description",
            aggregationType: "count_agg",
            group:
          }
        }
      )

      expect_unprocessable_entity(result)
    end
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: billable_metric.id,
            name: "New Metric",
            code: "new_metric",
            description: "New metric description",
            aggregationType: "count_agg"
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
