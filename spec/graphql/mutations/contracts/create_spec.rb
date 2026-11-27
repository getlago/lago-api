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
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:uuid_pattern) { /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/ }

  let(:input) do
    {
      externalCustomerId: customer.external_id,
      externalId: "contract-1",
      code: "initial",
      planCode: catalog_plan.code
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateContractInput!) {
        createContract(input: $input) {
          id externalId code status
          selectedInvoiceCustomSections { id }
          skipInvoiceCustomSections
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
    create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:))

    result_data = execution["data"]["createContract"]

    expect(result_data["id"]).to be_present
    expect(result_data["externalId"]).to eq("contract-1")
    expect(result_data["code"]).to eq("initial")
    expect(result_data["status"]).to eq("active")
    expect(result_data["plan"]["id"]).to eq(catalog_plan.id)
    expect(result_data["appliedRateCardsCount"]).to eq(1)
  end

  context "when the billing schedule is locked" do
    before { allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

    it "returns the existing concurrency error" do
      expect(execution["errors"].sole["extensions"]["code"]).to eq("lock_acquisition_failed")
      expect(organization.contracts).to be_empty
    end
  end

  context "with invoice custom sections" do
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:input) { super().merge(invoiceCustomSection: {invoiceCustomSectionIds: [section.id]}) }

    it "attaches the sections to the contract" do
      result_data = execution["data"]["createContract"]

      expect(result_data["selectedInvoiceCustomSections"].map { it["id"] }).to eq([section.id])
      expect(result_data["skipInvoiceCustomSections"]).to be(false)
    end
  end

  context "without a plan" do
    let(:input) { super().except(:planCode) }

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

  context "with the draft status" do
    let(:input) { super().merge(status: "draft", startedAt: 1.month.ago.iso8601) }

    it "creates a draft, even with a start that has passed" do
      expect(execution["data"]["createContract"]["status"]).to eq("draft")
    end

    context "without a start date" do
      let(:input) { super().except(:startedAt) }

      it "returns a validation error without creating a contract" do
        expect { execution }.not_to change(Contract, :count)
        expect_unprocessable_entity(execution, details: {startedAt: ["value_is_mandatory"]})
      end
    end
  end

  context "with a null status" do
    let(:input) { super().merge(status: nil) }

    it "creates the contract as when the status is omitted" do
      expect(execution["data"]["createContract"]["status"]).to eq("active")
    end
  end

  context "with a status other than draft" do
    let(:input) { super().merge(status: "active") }

    it "rejects it in the schema, as only a draft can be chosen" do
      expect { execution }.not_to change(Contract, :count)
      expect(execution["errors"].sole["message"]).to include('Expected "active" to be one of: draft')
    end
  end

  context "when a live contract already uses the external id" do
    before { create(:contract, organization:, customer:, external_id: "contract-1") }

    it "returns a validation error" do
      expect_unprocessable_entity(execution)
    end
  end

  context "without an external id" do
    let(:input) { super().except(:externalId) }

    it "generates one server-side and persists it" do
      result_data = execution["data"]["createContract"]

      expect(result_data["externalId"]).to match(uuid_pattern)
      expect(Contract.find(result_data["id"]).external_id).to eq(result_data["externalId"])
    end
  end

  context "with a blank external id" do
    let(:input) { super().merge(externalId: "") }

    it "treats it as omitted and generates one" do
      expect(execution["data"]["createContract"]["externalId"]).to match(uuid_pattern)
    end
  end

  context "with a whitespace-only external id" do
    let(:input) { super().merge(externalId: "  ") }

    it "treats it as omitted and generates one" do
      expect(execution["data"]["createContract"]["externalId"]).to match(uuid_pattern)
    end
  end
end
