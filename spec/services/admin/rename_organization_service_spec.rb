# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::RenameOrganizationService do
  subject(:result) { described_class.call(actor:, organization:, name:, reason:) }

  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, name: "Old Name") }
  let(:name) { "New Name" }
  let(:reason) { "Customer rebranded their company" }

  describe "#call" do
    it "renames the organization, creates an audit log, and enqueues the Slack job" do
      expect(result).to be_success
      expect(organization.reload.name).to eq("New Name")

      audit_log = result.audit_log
      expect(audit_log).to be_persisted
      expect(audit_log.actor_user).to eq(actor)
      expect(audit_log.action).to eq("org_renamed")
      expect(audit_log.feature_type).to eq("organization")
      expect(audit_log.feature_key).to eq("name")
      expect(audit_log.reason).to eq("Renamed from \"Old Name\" to \"New Name\". Customer rebranded their company")

      expect(Admin::SlackNotificationJob).to have_been_enqueued.with(audit_log.id)
    end

    context "when the name has surrounding spaces" do
      let(:name) { "  New Name  " }

      it "strips them" do
        expect(result).to be_success
        expect(organization.reload.name).to eq("New Name")
      end
    end

    context "when the organization does not exist" do
      let(:organization) { nil }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end

    context "when the name is blank" do
      let(:name) { "   " }

      it "returns a validation failure and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
        expect(organization.reload.name).to eq("Old Name")
        expect(CsAdminAuditLog.count).to eq(0)
      end
    end

    context "when the name is unchanged" do
      let(:name) { "Old Name" }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:name]).to eq(["value_is_unchanged"])
      end
    end

    context "when the reason is too short" do
      let(:reason) { "typo" }

      it "returns a validation failure and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages[:reason]).to eq(["value_is_too_short"])
        expect(organization.reload.name).to eq("Old Name")
      end
    end
  end
end
