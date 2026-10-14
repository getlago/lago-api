# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  before { allow(Utils::ActivityLog).to receive(:produce_after_commit) }

  it "terminates an active contract" do
    freeze_time do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.terminated", contract)
      expect(result).to be_success
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
      expect(contract.canceled_at).to be_nil
      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.terminated")
    end
  end

  context "when the clock activated the contract since it was loaded" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    before { Contract.where(id: contract.id).update_all(status: :active) } # rubocop:disable Rails/SkipsModelValidations

    it "terminates it instead of canceling it" do
      expect(result).to be_success
      expect(contract.reload.status).to eq("terminated")
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    it "cancels it instead of terminating" do
      freeze_time do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.canceled", contract)
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "canceled", canceled_at: Time.current)
        expect(contract.terminated_at).to be_nil
        expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.canceled")
      end
    end
  end

  context "when the contract is already terminated" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.terminated", any_args)
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.canceled", any_args)
    end
  end

  context "when the contract is already canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.terminated", any_args)
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.canceled", any_args)
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
