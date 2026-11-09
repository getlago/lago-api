# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Claims::StartService, :premium do
  subject(:result) { described_class.call(storefront:, params:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:claim) { create(:agent_claim, registration:, code: "ABCD2345") }
  let(:params) { {claim_code: "abcd-2345", email: "Owner@Example.com"} }

  before { claim }

  it "keeps the address on the claim and mails the verification code" do
    expect { result }.to have_enqueued_mail(Agents::ClaimMailer, :verification).with(params: {claim_id: claim.id}, args: [])

    expect(result).to be_success
    expect(result.claim).to eq(claim)
    expect(claim.reload).to have_attributes(status: "started", email: "Owner@Example.com", verification_code_hash: nil)
  end

  it "takes the latest address when the owner starts again, and drops the code mailed to the previous one" do
    described_class.call(storefront:, params: {claim_code: "ABCD2345", email: "first@example.com"})
    first_code = Agents::Claims::IssueVerificationCodeService.call!(claim:).code

    expect(result).to be_success
    expect(claim.reload).to have_attributes(email: "Owner@Example.com", verification_code_hash: nil, verification_expires_at: nil)

    verification = Agents::Claims::VerifyService.call(storefront:, params: {claim_code: "ABCD2345", verification_code: first_code})
    expect(verification.error.messages).to eq(verification_code: ["invalid_verification_code"])
  end

  context "when the code is unknown" do
    let(:params) { {claim_code: "ABCD2346", email: "owner@example.com"} }

    it "refuses with the one word used for every bad code" do
      expect(result.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end

  context "when the code was already used" do
    let(:claim) { create(:agent_claim, :verified, registration:, code: "ABCD2345") }

    it "refuses with the same word, so nothing leaks" do
      expect(result.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end

  context "when the code belongs to another storefront" do
    let(:claim) { create(:agent_claim, code: "ABCD2345") }

    it "is not found here" do
      expect(result.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end

  context "when the agent was revoked" do
    before { registration.update!(status: :revoked, revoked_at: Time.current) }

    it "refuses" do
      expect(result.error.messages).to eq(base: ["registration_inactive"])
    end
  end

  context "when the e-mail is not one valid address" do
    it "refuses a malformed address and a list" do
      ["not an email", "a@example.com, b@example.com", "a@example.com,b@example.com", ""].each do |email|
        failure = described_class.call(storefront:, params: {claim_code: "ABCD2345", email:})

        expect(failure.error.messages).to eq(email: ["invalid_email_format"])
      end
      expect(claim.reload).to be_issued
    end
  end

  context "when the mailbox has had its mails for the hour" do
    before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

    it "refuses the fourth mail, also for a +tag alias, and only counts mails that pass the checks" do
      described_class.call(storefront:, params: {claim_code: "WRONG", email: "owner@example.com"})
      3.times { expect(described_class.call(storefront:, params: {claim_code: "ABCD2345", email: "owner@example.com"})).to be_success }

      refused = described_class.call(storefront:, params: {claim_code: "ABCD2345", email: "owner+agent2@example.com"})

      expect(refused.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(refused.error.code).to eq("too_many_requests")
    end
  end

  context "when the claim is deleted after it was found" do
    it "answers as for an unknown code" do
      # The agent asked for a new code between the lookup and the lock. The instance is used so the lookup can be
      # forced before the row disappears.
      service = described_class.new(storefront:, params:)
      service.send(:claim)
      Agents::Claim.where(id: claim.id).delete_all

      failure = service.call

      expect(failure.error.messages).to eq(claim_code: ["invalid_claim_code"])
    end
  end
end
