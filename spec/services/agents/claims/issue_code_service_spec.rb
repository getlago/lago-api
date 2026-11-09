# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Claims::IssueCodeService, :premium do
  subject(:result) { described_class.call(registration:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:customer) { create(:customer, organization:, external_id: "agent_#{registration.id}") }

  before { customer }

  it "issues a code and stores only its digest" do
    expect(result).to be_success
    expect(result.code).to match(/\A[#{Agents::Claim::CODE_ALPHABET}]{8}\z/)
    expect(result.claim).to have_attributes(
      organization:, registration:, status: "issued", code_hash: Agents::Claim.digest(result.code), email: nil
    )
  end

  it "replaces the previous codes of the registration, whether used or not" do
    issued = create(:agent_claim, registration:)
    started = create(:agent_claim, :started, registration:)
    other = create(:agent_claim, registration: create(:agent_registration, storefront:))

    expect(result).to be_success
    expect(registration.claims).to contain_exactly(result.claim)
    expect(Agents::Claim.where(id: [issued.id, started.id])).to be_empty
    expect(other.reload).to be_persisted
  end

  context "when the agent is not enrolled" do
    let(:customer) { nil }

    it "refuses: the e-mail would have no customer to land on" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["enrollment_required"])
      expect(Agents::Claim.count).to eq(0)
    end
  end

  context "when the agent is already claimed" do
    let!(:verified) { create(:agent_claim, :verified, registration:) }

    it "refuses and keeps the verified claim" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["registration_already_claimed"])
      expect(registration.claims).to contain_exactly(verified)
    end
  end
end
