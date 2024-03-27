# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Plans::Destroy, type: :graphql do
  subject(:graphql_request) do
    execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {input: {id: plan.id}}
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: membership.organization) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyPlanInput!) {
        destroyPlan(input: $input) {
          id
        }
      }
    GQL
  end

  it "marks plan as pending_deletion" do
    expect { graphql_request }.to change { plan.reload.pending_deletion }.from(false).to(true)
  end

  it "returns the deleted plan" do
    data = graphql_request["data"]["destroyPlan"]
    expect(data["id"]).to eq(plan.id)
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {input: {id: plan.id}}
      )

      expect_unauthorized_error(result)
    end
  end
end
