# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  it "terminates an active contract" do
    freeze_time do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
      expect(contract.canceled_at).to be_nil
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    it "cancels it instead of terminating" do
      freeze_time do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "canceled", canceled_at: Time.current)
        expect(contract.terminated_at).to be_nil
      end
    end
  end

  context "when the contract is already terminated" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
    end
  end

  context "when the contract is already canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
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
