# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "contracts:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, :product_catalog, organization:) }

  let(:input) do
    {
      externalCustomerId: customer.external_id,
      externalId: "contract-1",
      planCode: plan.code
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateContractInput!) {
        createContract(input: $input) {
          id externalId status billingTime
          plan { id }
          appliedRateCards { id }
          appliedRateCardsCount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:create"

  it "creates a contract and materializes the plan's rate cards" do
    create(:plan_rate_card, organization:, plan:, rate_card: create(:rate_card, organization:))

    result_data = execution["data"]["createContract"]

    expect(result_data["id"]).to be_present
    expect(result_data["externalId"]).to eq("contract-1")
    expect(result_data["status"]).to eq("active")
    expect(result_data["billingTime"]).to eq("calendar")
    expect(result_data["plan"]["id"]).to eq(plan.id)
    expect(result_data["appliedRateCardsCount"]).to eq(1)
  end

  context "without a plan" do
    let(:input) { {externalCustomerId: customer.external_id, externalId: "contract-1"} }

    it "creates a plan-less contract" do
      result_data = execution["data"]["createContract"]

      expect(result_data["plan"]).to be_nil
      expect(result_data["appliedRateCards"]).to be_empty
    end
  end

  context "with a future start" do
    let(:input) { super().merge(startedAt: 1.month.from_now.iso8601) }

    it "creates a pending contract" do
      expect(execution["data"]["createContract"]["status"]).to eq("pending")
    end
  end

  context "when a live contract already uses the external id" do
    before { create(:contract, organization:, customer:, external_id: "contract-1") }

    it "returns a validation error" do
      expect_unprocessable_entity(execution)
    end
  end
end
