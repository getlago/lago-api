# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::CreateWithInviteService do
  subject(:result) do
    described_class.call(name:, owner_email: "owner@hooli.test", document_numbering: "per_customer",
      premium_integrations: [], feature_flags: ["order_forms"], self_serve:)
  end

  let(:name) { "Hooli" }
  let(:self_serve) { false }

  before { create(:role, :admin) }

  it "creates the organization and invites its owner" do
    organization = result.organization

    expect(organization).to have_attributes(name: "Hooli", self_serve: false, environment: "production",
      document_numbering: "per_customer", feature_flags: ["order_forms"])
    expect(result.sandbox_organization).to be_nil
    expect(Invite.where(organization:).sole).to have_attributes(email: "owner@hooli.test")
    expect(result.invite_url).to include("/invitation/#{Invite.sole.token}")
  end

  context "with a name that reads as a domain" do
    let(:name) { "Hooli.com" }

    it "accepts it" do
      expect(result.organization.name).to eq("Hooli.com")
    end
  end

  context "with self_serve" do
    include_context "with self-serve enabled"

    let(:self_serve) { true }

    it "creates the pair with the given settings and invites the owner to production only" do
      production = result.organization
      sandbox = result.sandbox_organization

      expect([production, sandbox].map { [it.name, it.environment, it.document_numbering, it.feature_flags] }).to eq([
        ["Hooli", "production", "per_customer", ["order_forms"]],
        ["Hooli Sandbox", "sandbox", "per_customer", ["order_forms"]]
      ])
      expect(sandbox.production_organization_id).to eq(production.id)
      expect(Invite.pluck(:organization_id, :email)).to eq([[production.id, "owner@hooli.test"]])
    end

    context "with a name that reads as a domain" do
      let(:name) { "Hooli.com" }

      it "accepts it" do
        expect([result.organization.name, result.sandbox_organization.name]).to eq(["Hooli.com", "Hooli.com Sandbox"])
      end
    end

    context "when self-serve is off" do
      let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "false"} }

      it "refuses it and creates nothing" do
        expect { result }.not_to change { [Organization.count, Invite.count] }
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("self_serve_disabled")
      end
    end
  end

  context "with a self_serve that is not a boolean" do
    let(:self_serve) { "no" }

    it "refuses it and creates nothing" do
      expect { result }.not_to change(Organization, :count)
      expect(result.error.messages).to eq(self_serve: ["value_is_invalid"])
    end
  end

  context "when the invite cannot be created" do
    subject(:result) do
      described_class.call(name:, owner_email: "not-an-email", document_numbering: "per_customer", self_serve: true)
    end

    include_context "with self-serve enabled"

    it "creates neither organization" do
      expect { result }.not_to change(Organization, :count)
      expect(result.error.messages).to eq(email: ["invalid_email_format"])
    end
  end
end
