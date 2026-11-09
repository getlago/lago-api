# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Claims::VerifyService, :premium do
  subject(:result) { described_class.call(storefront:, params:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:customer) { create(:customer, organization:, external_id: "agent_#{registration.id}", email: nil) }
  let(:claim) do
    create(
      :agent_claim, :started, registration:, code: "ABCD2345", email: "owner@example.com",
      verification_code_hash: Agents::Claim.digest("123456"), verification_expires_at: 10.minutes.from_now
    )
  end
  let(:params) { {claim_code: "abcd-2345", verification_code: "123 456"} }

  before do
    customer
    claim
  end

  it "verifies the claim and gives the customer the e-mail, in one transaction" do
    freeze_time do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("customer.updated", customer)

      expect(result).to be_success
      expect(claim.reload).to have_attributes(status: "verified", verified_at: Time.current, email: nil)
      expect(customer.reload.email).to eq("owner@example.com")
    end
  end

  it "refuses a second verification: the code is spent" do
    described_class.call(storefront:, params:)

    expect(result.error.messages).to eq(claim_code: ["invalid_claim_code"])
  end

  context "when the typed code is wrong" do
    let(:params) { {claim_code: "ABCD2345", verification_code: "123457"} }

    it "refuses and changes nothing" do
      expect(result.error.messages).to eq(verification_code: ["invalid_verification_code"])
      expect(claim.reload).to be_started
      expect(customer.reload.email).to be_nil
    end
  end

  context "when no code was mailed yet" do
    before { claim.update!(verification_code_hash: nil, verification_expires_at: nil) }

    it "refuses as a wrong code, not as expired" do
      expect(result.error.messages).to eq(verification_code: ["invalid_verification_code"])
    end
  end

  context "when the mailed code expired" do
    it "refuses and leaves the claim started, so the owner can start again" do
      travel_to(11.minutes.from_now) do
        expect(result.error.messages).to eq(verification_code: ["verification_expired"])
      end
      expect(claim.reload).to be_started
    end
  end

  context "when the claim was never started" do
    let(:claim) { create(:agent_claim, registration:, code: "ABCD2345") }

    it "refuses as an unknown code" do
      expect(result.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end

  context "when the agent was revoked" do
    before { registration.update!(status: :revoked, revoked_at: Time.current) }

    it "refuses" do
      expect(result.error.messages).to eq(base: ["registration_inactive"])
    end
  end

  context "when the customer was deleted meanwhile" do
    before { customer.discard! }

    it "refuses and leaves the claim started" do
      expect(result.error.messages).to eq(base: ["enrollment_required"])
      expect(claim.reload).to be_started
    end
  end

  context "when the claim is deleted after it was found" do
    it "answers as for an unknown code" do
      # The agent asked for a new code between the lookup and the lock.
      service = described_class.new(storefront:, params:)
      service.send(:claim)
      Agents::Claim.where(id: claim.id).delete_all

      failure = service.call

      expect(failure.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end
end
