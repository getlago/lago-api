# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ToggleFeatureService do
  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }

  before do
    stub_const("Admin::EmailNotificationJob", Class.new do
      def self.perform_later(*); end
    end)
    allow(Admin::SlackNotificationJob).to receive(:perform_later)
    allow(Admin::EmailNotificationJob).to receive(:perform_later)
  end

  describe "#call" do
    context "when toggling a premium integration ON" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "premium_integration",
          feature_key: "okta",
          enabled: true,
          reason: "Enabling okta for testing purposes",
          notify_org_admin: false
        )
      end

      it "adds the integration, creates an audit log, and enqueues Slack job" do
        result = service.call

        expect(result).to be_success
        expect(organization.reload.premium_integrations).to include("okta")

        audit_log = result.audit_log
        expect(audit_log).to be_a(CsAdminAuditLog)
        expect(audit_log.actor_user).to eq(actor)
        expect(audit_log.actor_email).to eq("cs@getlago.com")
        expect(audit_log.action).to eq("toggle_on")
        expect(audit_log.organization).to eq(organization)
        expect(audit_log.feature_type).to eq("premium_integration")
        expect(audit_log.feature_key).to eq("okta")
        expect(audit_log.before_value).to be(false)
        expect(audit_log.after_value).to be(true)
        expect(audit_log.reason).to eq("Enabling okta for testing purposes")

        expect(Admin::SlackNotificationJob).to have_received(:perform_later).with(audit_log.id)
      end
    end

    context "when toggling a premium integration OFF" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "premium_integration",
          feature_key: "okta",
          enabled: false,
          reason: "Disabling okta for testing purposes",
          notify_org_admin: false
        )
      end

      before { organization.update!(premium_integrations: ["okta"]) }

      it "removes the integration and records toggle_off action" do
        result = service.call

        expect(result).to be_success
        expect(organization.reload.premium_integrations).not_to include("okta")

        audit_log = result.audit_log
        expect(audit_log.action).to eq("toggle_off")
        expect(audit_log.before_value).to be(true)
        expect(audit_log.after_value).to be(false)
      end
    end

    context "when toggling a feature flag ON" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "feature_flag",
          feature_key: "multiple_payment_methods",
          enabled: true,
          reason: "Enabling feature flag for testing purposes",
          notify_org_admin: false
        )
      end

      it "calls enable_feature_flag! and creates an audit log" do
        allow(organization).to receive(:enable_feature_flag!).and_call_original

        result = service.call

        expect(result).to be_success
        expect(organization).to have_received(:enable_feature_flag!).with("multiple_payment_methods")

        audit_log = result.audit_log
        expect(audit_log.action).to eq("toggle_on")
        expect(audit_log.feature_type).to eq("feature_flag")
        expect(audit_log.feature_key).to eq("multiple_payment_methods")
      end
    end

    context "when toggling a feature flag OFF" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "feature_flag",
          feature_key: "multiple_payment_methods",
          enabled: false,
          reason: "Disabling feature flag for testing purposes",
          notify_org_admin: false
        )
      end

      it "calls disable_feature_flag! and creates an audit log" do
        allow(organization).to receive(:disable_feature_flag!).and_call_original

        result = service.call

        expect(result).to be_success
        expect(organization).to have_received(:disable_feature_flag!).with("multiple_payment_methods")

        audit_log = result.audit_log
        expect(audit_log.action).to eq("toggle_off")
        expect(audit_log.feature_type).to eq("feature_flag")
      end
    end

    context "when feature_key is invalid" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "premium_integration",
          feature_key: "not_a_real_integration",
          enabled: true,
          reason: "This should fail validation",
          notify_org_admin: false
        )
      end

      it "returns a validation failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:feature_key]).to include("invalid")
      end
    end

    context "when organization is nil" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: nil,
          feature_type: "premium_integration",
          feature_key: "okta",
          enabled: true,
          reason: "This should fail with not found",
          notify_org_admin: false
        )
      end

      it "returns a not found failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("organization")
      end
    end

    context "when notify_org_admin is true" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "premium_integration",
          feature_key: "okta",
          enabled: true,
          reason: "Enabling okta for testing purposes",
          notify_org_admin: true
        )
      end

      it "enqueues an email notification job" do
        result = service.call

        expect(result).to be_success
        expect(Admin::EmailNotificationJob).to have_received(:perform_later).with(result.audit_log.id, "cs@getlago.com")
      end
    end

    context "when notify_org_admin is false" do
      subject(:service) do
        described_class.new(
          actor: actor,
          organization: organization,
          feature_type: "premium_integration",
          feature_key: "okta",
          enabled: true,
          reason: "Enabling okta for testing purposes",
          notify_org_admin: false
        )
      end

      it "does not enqueue an email notification job" do
        service.call

        expect(Admin::EmailNotificationJob).not_to have_received(:perform_later)
      end
    end
  end
end
