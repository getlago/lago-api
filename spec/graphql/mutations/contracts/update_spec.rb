# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "contracts:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:input) { {externalId: contract.external_id, name: "Renamed"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateContractInput!) {
        updateContract(input: $input) {
          id externalId name
          plan { id }
          appliedRateCards { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "updates the contract" do
    result_data = execution["data"]["updateContract"]

    expect(result_data["externalId"]).to eq(contract.external_id)
    expect(result_data["name"]).to eq("Renamed")
  end

  context "when targeting the contract by id" do
    let(:input) { {id: contract.id, name: "Renamed"} }

    it "updates the contract" do
      result_data = execution["data"]["updateContract"]

      expect(result_data["id"]).to eq(contract.id)
      expect(result_data["name"]).to eq("Renamed")
    end
  end

  context "with an active contract and a pending sibling sharing its external id" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, name: "Active") }
    let(:pending_contract) do
      create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: contract.external_id, name: "Pending")
    end

    before { pending_contract }

    context "when targeting the active contract by id" do
      let(:input) { {id: contract.id, name: "Renamed"} }

      it "updates the active contract only" do
        expect(execution["data"]["updateContract"]["id"]).to eq(contract.id)
        expect(contract.reload.name).to eq("Renamed")
        expect(pending_contract.reload.name).to eq("Pending")
      end
    end

    context "when targeting by external id" do
      it "updates the pending contract" do
        expect(execution["data"]["updateContract"]["id"]).to eq(pending_contract.id)
        expect(contract.reload.name).to eq("Active")
      end
    end
  end

  context "when the id belongs to another organization" do
    let(:input) { {id: create(:contract, :pending).id, name: "Renamed"} }

    it "returns a not found error" do
      expect_not_found(execution)
    end
  end

  context "without id nor external id" do
    let(:input) { {name: "Renamed"} }

    it "returns an error" do
      expect_graphql_error(
        result: execution,
        message: "UpdateContractInput must include exactly one of the following arguments: id, externalId."
      )
    end
  end

  context "with both id and external id" do
    let(:input) { {id: contract.id, externalId: contract.external_id, name: "Renamed"} }

    it "returns an error" do
      expect_graphql_error(
        result: execution,
        message: "UpdateContractInput must include exactly one of the following arguments: id, externalId."
      )
    end
  end

  context "when changing the plan" do
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:input) { {externalId: contract.external_id, planCode: other_plan.code} }

    it "re-materializes the rate cards from the new plan" do
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: create(:rate_card, organization:))

      result_data = execution["data"]["updateContract"]

      expect(result_data["plan"]["id"]).to eq(other_plan.id)
      expect(result_data["appliedRateCards"].size).to eq(1)
    end
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    it "updates the fields that stay editable" do
      expect(execution["data"]["updateContract"]["name"]).to eq("Renamed")
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:input) { {externalId: contract.external_id, planCode: other_plan.code} }

      it "returns a validation error" do
        expect_unprocessable_entity(execution)
      end
    end

    context "when the form resends the locked fields unchanged" do
      let(:input) do
        {
          externalId: contract.external_id,
          name: "Renamed",
          planCode: catalog_plan.code,
          billingTime: "calendar",
          startedAt: contract.started_at.iso8601,
          billingAnchorDate: contract.effective_billing_anchor_date.iso8601
        }
      end

      it "updates the contract" do
        expect(execution["data"]["updateContract"]["name"]).to eq("Renamed")
      end
    end
  end
end
