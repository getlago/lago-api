# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::TrackContractActivityService, :premium do
  subject(:result) { described_class.call(contract:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:contract) { create(:contract, organization:, customer:) }
  let(:alert) { create(:contract_usage_amount_alert, organization: contract.organization, contract_external_id: contract.external_id) }

  before { alert }

  it "tracks the contract" do
    expect { result }.to change(UsageMonitoring::ContractActivity, :count).by(1)

    expect(result).to be_success
    expect(UsageMonitoring::ContractActivity.sole).to have_attributes(
      organization_id: organization.id,
      contract_id: contract.id,
      enqueued: false,
      enqueued_at: nil
    )
  end

  it "tracks the contract once however many times it is called" do
    described_class.call(contract:)

    expect { result }.not_to change(UsageMonitoring::ContractActivity, :count)
  end

  context "when the row of the contract is already enqueued" do
    let(:contract_activity) do
      create(:contract_activity, organization:, contract:, enqueued: true, enqueued_at: 10.seconds.ago)
    end

    before { contract_activity }

    it "keeps it as it is, for the job already on its way" do
      expect { result }.not_to change { contract_activity.reload.attributes }
      expect(UsageMonitoring::ContractActivity.sole).to eq(contract_activity)
    end
  end

  context "when another contract is tracked" do
    before { create(:contract_activity, organization:) }

    it "tracks this one too" do
      expect { result }.to change(UsageMonitoring::ContractActivity, :count).by(1)
      expect(UsageMonitoring::ContractActivity.where(contract:)).to exist
    end
  end

  %i[draft pending terminated canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "does not track it" do
        expect(result).to be_success
        expect(UsageMonitoring::ContractActivity.count).to eq(0)
      end
    end
  end

  context "when the contract has no alert" do
    let(:alert) { nil }

    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "when the only alert of the contract is deleted" do
    before { alert.discard! }

    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "when only another contract has an alert" do
    let(:alert) { create(:contract_usage_amount_alert, organization:) }

    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "when only another organization has an alert on the external id" do
    let(:alert) do
      create(:contract_usage_amount_alert, organization: create(:organization), contract_external_id: contract.external_id)
    end

    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "when the alert follows the external id of a contract replaced since" do
    let(:previous_contract) { create(:contract, :terminated, organization:, customer:) }
    let(:contract) { create(:contract, organization:, customer:, external_id: previous_contract.external_id) }
    let(:alert) { create(:contract_usage_amount_alert, organization:, contract_external_id: previous_contract.external_id) }

    it "tracks the active contract" do
      expect { result }.to change(UsageMonitoring::ContractActivity, :count).by(1)
      expect(UsageMonitoring::ContractActivity.sole.contract_id).to eq(contract.id)
    end
  end

  context "without the contract_alerts flag" do
    let(:contract) do
      other_organization = create(:organization, feature_flags: %w[product_catalog])
      create(:contract, organization: other_organization, customer: create(:customer, organization: other_organization))
    end

    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "without a premium license", premium: false do
    it "does not track it" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end
end
