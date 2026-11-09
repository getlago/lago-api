# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ClaimMailer, :premium do
  subject(:mail) { described_class.with(claim_id: claim.id).verification }

  let(:organization) { create(:organization, name: "Acme", premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:, name: "Acme API") }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:customer) { create(:customer, organization:, external_id: "agent_#{registration.id}") }
  let(:billing_entity) { customer.billing_entity }
  let(:claim) { create(:agent_claim, :started, registration:, email: "Owner@Example.com") }

  before do
    billing_entity.update!(name: "Acme Billing", email: nil)
    claim
  end

  def mailed_code(mail)
    digest = claim.reload.verification_code_hash
    CGI.unescapeHTML(mail.body.encoded).scan(/\b\d{6}\b/).find { Agents::Claim.digest(it) == digest }
  end

  it "mails a six-digit code from the merchant, issued inside the mailer" do
    freeze_time do
      body = CGI.unescapeHTML(mail.body.encoded)

      expect(mail.to).to eq(["Owner@Example.com"])
      expect(mail.from).to eq([ENV["LAGO_FROM_EMAIL"]])
      expect(mail[:from].display_names).to eq(["Acme Billing"])
      expect(mail.reply_to).to be_nil
      expect(mail.subject).to eq("Your code to claim an agent on Acme API")
      expect(mailed_code(mail)).to be_present
      expect(claim.reload.verification_expires_at).to eq(10.minutes.from_now)
      expect(body).to include("confirm that you own the agent #{registration.id} on Acme API")
      expect(body).to include("This code is valid for 10 minutes and works once.")
      expect(body).to include("Acme")
    end
  end

  it "takes only the claim id as a param" do
    expect(mail.instance_variable_get(:@params)).to eq(claim_id: claim.id)
  end

  context "when the billing entity has an e-mail and sends from it" do
    before do
      organization.update!(premium_integrations: %w[agent_storefront from_email])
      billing_entity.update!(email: "billing@acme.test")
    end

    it "uses it as sender and reply-to" do
      expect(mail.from).to eq(["billing@acme.test"])
      expect(mail.reply_to).to eq(["billing@acme.test"])
    end
  end

  shared_examples "sends nothing" do
    it "sends nothing and issues no code" do
      expect(mail.to).to be_nil
      expect(Agents::Claim.find_by(id: claim.id)&.verification_code_hash).to be_nil
    end
  end

  context "when the claim no longer exists" do
    subject(:mail) { described_class.with(claim_id: SecureRandom.uuid).verification }

    include_examples "sends nothing"
  end

  context "when the claim was verified meanwhile" do
    before { claim.update!(status: :verified, verified_at: Time.current, email: nil) }

    include_examples "sends nothing"
  end

  context "when the agent was revoked" do
    before { registration.update!(status: :revoked, revoked_at: Time.current) }

    include_examples "sends nothing"
  end

  context "when the customer was deleted" do
    before { customer.discard! }

    include_examples "sends nothing"
  end

  context "when the organization lost the feature" do
    before { organization.update!(premium_integrations: []) }

    include_examples "sends nothing"
  end
end
