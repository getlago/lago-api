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

  let(:input) { {id: contract.id, name: "Renamed"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateContractInput!) {
        updateContract(input: $input) {
          id externalId name
          selectedInvoiceCustomSections { id }
          skipInvoiceCustomSections
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

  context "when the billing schedule is locked" do
    before { allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

    it "returns the existing concurrency error without changing the contract" do
      expect { execution }.not_to change { contract.reload.attributes }
      expect(execution["errors"].sole["extensions"]["code"]).to eq("lock_acquisition_failed")
    end
  end

  context "with invoice custom sections" do
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:input) { {id: contract.id, invoiceCustomSection: {invoiceCustomSectionIds: [section.id]}} }

    it "attaches the sections to the contract" do
      expect(execution["data"]["updateContract"]["selectedInvoiceCustomSections"].map { it["id"] }).to eq([section.id])
    end
  end

  context "when skipping invoice custom sections" do
    let(:input) { {id: contract.id, invoiceCustomSection: {skipInvoiceCustomSections: true}} }

    before { create(:contract_applied_invoice_custom_section, organization:, contract:) }

    it "flags the contract and drops its sections" do
      result_data = execution["data"]["updateContract"]

      expect(result_data["skipInvoiceCustomSections"]).to be(true)
      expect(result_data["selectedInvoiceCustomSections"]).to be_empty
    end
  end

  context "when changing the plan" do
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:input) { {id: contract.id, planCode: other_plan.code} }

    it "re-materializes the rate cards from the new plan" do
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: create(:rate_card, organization:))

      result_data = execution["data"]["updateContract"]

      expect(result_data["plan"]["id"]).to eq(other_plan.id)
      expect(result_data["appliedRateCards"].size).to eq(1)
    end
  end

  context "when the contract is a draft" do
    let(:contract) { create(:contract, :draft, organization:, customer:, catalog_plan:, started_at: 1.month.from_now) }
    let(:input) { {id: contract.id, name: "Renamed", startedAt: "2026-10-01T00:00:00Z"} }

    before { travel_to(Time.zone.parse("2026-11-01")) }

    it "updates it and keeps it a draft, even with a start that has passed" do
      expect(execution["data"]["updateContract"]["name"]).to eq("Renamed")
      expect(contract.reload).to have_attributes(status: "draft", started_at: Time.zone.parse("2026-10-01"))
    end
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    it "updates the fields that stay editable" do
      expect(execution["data"]["updateContract"]["name"]).to eq("Renamed")
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:input) { {id: contract.id, planCode: other_plan.code} }

      it "returns a validation error" do
        expect_unprocessable_entity(execution)
      end
    end

    context "when the form resends the locked fields unchanged" do
      let(:input) do
        {
          id: contract.id,
          name: "Renamed",
          planCode: catalog_plan.code,
          startedAt: contract.started_at.iso8601,
          billingAnchorDate: contract.effective_billing_anchor_date.iso8601
        }
      end

      it "updates the contract" do
        expect(execution["data"]["updateContract"]["name"]).to eq("Renamed")
      end
    end
  end

  context "when an active contract has a pending replacement" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:replacement) { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

    before { replacement }

    it "updates the selected contract, not its pending replacement" do
      result_data = execution["data"]["updateContract"]

      expect(result_data["id"]).to eq(contract.id)
      expect(contract.reload.name).to eq("Renamed")
      expect(replacement.reload.name).to be_nil
    end
  end

  %i[terminated canceled].each do |status|
    context "when the selected contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:, catalog_plan:) }
      let(:live_sibling) { create(:contract, organization:, customer:, external_id: contract.external_id) }

      before { live_sibling }

      it "returns its lifecycle error without updating the live sibling" do
        expect_unprocessable_entity(execution, details: {contract: ["contract_locked"]})
        expect(contract.reload.name).to be_nil
        expect(live_sibling.reload.name).to be_nil
      end
    end
  end

  context "when the contract belongs to another organization" do
    let(:foreign_contract) { create(:contract, :pending, external_id: contract.external_id) }
    let(:input) { {id: foreign_contract.id, name: "Renamed"} }

    it "does not update either organization's contract" do
      expect_not_found(execution, details: {contract: ["not_found"]})
      expect(foreign_contract.reload.name).to be_nil
      expect(contract.reload.name).to be_nil
    end
  end

  context "when the id does not exist" do
    let(:input) { super().merge(id: SecureRandom.uuid) }

    it "returns a not found error" do
      expect_not_found(execution, details: {contract: ["not_found"]})
    end
  end

  context "when an external id is sent as the id" do
    let(:input) { super().merge(id: contract.external_id) }

    it "does not use an external-id fallback" do
      expect_not_found(execution, details: {contract: ["not_found"]})
      expect(contract.reload.name).to be_nil
    end
  end

  context "when only externalId is supplied" do
    let(:input) { {externalId: contract.external_id, name: "Renamed"} }

    it "rejects the input without updating the contract" do
      expect(execution["errors"]).not_to be_empty
      expect(contract.reload.name).to be_nil
    end
  end
end
