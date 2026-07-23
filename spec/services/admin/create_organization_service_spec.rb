# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CreateOrganizationService do
  subject(:service) do
    described_class.new(
      actor: actor,
      name: name,
      owner_email: owner_email,
      timezone: timezone,
      premium_integrations: premium_integrations,
      feature_flags: feature_flags,
      reason: reason
    )
  end

  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:name) { "Hooli Inc" }
  let(:owner_email) { "owner@hooli.com" }
  let(:timezone) { nil }
  let(:premium_integrations) { ["okta", "netsuite"] }
  let(:feature_flags) { ["multi_currency"] }
  let(:reason) { "New enterprise customer onboarding" }

  before do
    create(:role, :admin)
  end

  describe "#call" do
    it "creates an organization using Organizations::CreateService" do
      result = service.call

      expect(result).to be_success
      organization = result.organization
      expect(organization).to be_a(Organization)
      expect(organization.name).to eq("Hooli Inc")
    end

    it "sets premium integrations on the organization" do
      result = service.call

      expect(result.organization.premium_integrations).to match_array(["okta", "netsuite"])
    end

    it "sets feature flags on the organization" do
      result = service.call

      expect(result.organization.reload.feature_flags).to include("multi_currency")
    end

    it "creates an invite for the owner email and returns the invite url" do
      result = service.call
      organization = result.organization

      invite = Invite.find_by(organization: organization, email: owner_email)
      expect(invite).to be_present
      expect(result.invite_url).to include("/invitation/#{invite.token}")
    end

    it "creates audit logs for premium integrations and feature flags" do
      result = service.call
      organization = result.organization

      logs = CsAdminAuditLog.where(organization:)
      expect(logs.count).to eq(3)
      expect(logs.pluck(:action).uniq).to eq(["org_created"])
      expect(logs.pluck(:batch_id).uniq.count).to eq(1)

      integration_logs = logs.where(feature_type: "premium_integration")
      expect(integration_logs.pluck(:feature_key)).to match_array(["okta", "netsuite"])

      flag_logs = logs.where(feature_type: "feature_flag")
      expect(flag_logs.pluck(:feature_key)).to eq(["multi_currency"])

      logs.each do |log|
        expect(log.actor_user).to eq(actor)
        expect(log.actor_email).to eq("cs@getlago.com")
        expect(log.before_value).to be_nil
        expect(log.after_value).to be(true)
        expect(log.reason).to eq("New enterprise customer onboarding")
      end
    end

    it "enqueues a Slack notification job for each audit log" do
      result = service.call
      organization = result.organization

      log_ids = CsAdminAuditLog.where(organization:).pluck(:id)
      expect(log_ids.count).to eq(3)

      log_ids.each do |log_id|
        expect(Admin::SlackNotificationJob).to have_been_enqueued.with(log_id)
      end
    end

    context "when no premium integrations or feature flags are provided" do
      subject(:service) do
        described_class.new(
          actor: actor,
          name: name,
          owner_email: owner_email,
          reason: reason
        )
      end

      it "creates an organization with no audit logs" do
        result = service.call

        expect(result).to be_success
        expect(CsAdminAuditLog.where(organization: result.organization).count).to eq(0)
        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end
  end
end
