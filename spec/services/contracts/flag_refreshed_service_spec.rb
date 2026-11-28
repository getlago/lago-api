# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::FlagRefreshedService, :premium do
  subject(:result) { described_class.call(organization_id:, external_contract_id:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:organization_id) { organization.id }
  let(:external_contract_id) { contract.external_id }
  let(:contract) { create(:contract, organization:, customer:) }

  before do
    create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id)
  end

  it "tracks the contract activity" do
    expect { result }.to change(UsageMonitoring::ContractActivity, :count).by(1)

    expect(result).to be_success
    expect(UsageMonitoring::ContractActivity.sole).to have_attributes(
      organization_id: organization.id,
      contract_id: contract.id
    )
  end

  context "when a pending replacement shares the external id" do
    let(:pending_contract) { create(:contract, :pending, organization:, customer:, external_id: contract.external_id) }

    before { pending_contract }

    it "tracks the active contract only" do
      expect { result }.to change(UsageMonitoring::ContractActivity, :count).by(1)
      expect(UsageMonitoring::ContractActivity.sole.contract_id).to eq(contract.id)
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }

    it "does not track the contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when the contract belongs to another organization" do
    let(:other_organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
    let(:contract) { create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization)) }

    before do
      create(:contract_usage_amount_alert, organization: other_organization, contract_external_id: contract.external_id)
    end

    it "does not track the contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when no contract has the external id" do
    let(:external_contract_id) { "unknown" }

    it "does not track any contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when the organization does not exist" do
    let(:organization_id) { SecureRandom.uuid }

    it "does not track any contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when the organization id is not a uuid" do
    let(:organization_id) { "not-a-uuid" }

    it "does not track any contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when the contract_alerts flag is off" do
    let(:organization) { create(:organization, feature_flags: %w[product_catalog]) }
    let(:customer) { create(:customer, organization:) }

    it "does not track the contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end

  context "when the product_catalog flag is off" do
    let(:organization) { create(:organization, feature_flags: %w[contract_alerts]) }
    let(:customer) { create(:customer, organization:) }

    it "does not track the contract activity" do
      expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
      expect(result).to be_success
    end
  end
end
