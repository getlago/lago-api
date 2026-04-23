# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::RollbackService do
  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }

  before do
    allow(Admin::SlackNotificationJob).to receive(:perform_later)
  end

  describe "#call" do
    context "when rolling back a toggle_on (disabling the feature)" do
      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_on,
          organization: organization,
          feature_type: :premium_integration,
          feature_key: "okta",
          before_value: false,
          after_value: true,
          reason: "Enabling okta for testing purposes"
        )
      end

      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back okta toggle for testing"
        )
      end

      before { organization.update!(premium_integrations: ["okta"]) }

      it "disables the feature and creates a rollback audit log" do
        result = service.call

        expect(result).to be_success
        expect(organization.reload.premium_integrations).not_to include("okta")

        rollback_log = result.audit_log
        expect(rollback_log).to be_a(CsAdminAuditLog)
        expect(rollback_log.action).to eq("rollback")
        expect(rollback_log.actor_user).to eq(actor)
        expect(rollback_log.actor_email).to eq("cs@getlago.com")
        expect(rollback_log.organization).to eq(organization)
        expect(rollback_log.feature_type).to eq("premium_integration")
        expect(rollback_log.feature_key).to eq("okta")
        expect(rollback_log.before_value).to be(true)
        expect(rollback_log.after_value).to be(false)
        expect(rollback_log.reason).to eq("Rolling back okta toggle for testing")
        expect(rollback_log.rollback_of).to eq(original_log)
        expect(rollback_log.batch_id).to eq(original_log.batch_id)
      end
    end

    context "when rolling back a toggle_off (re-enabling the feature)" do
      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_off,
          organization: organization,
          feature_type: :premium_integration,
          feature_key: "netsuite",
          before_value: true,
          after_value: false,
          reason: "Disabling netsuite for cost reasons"
        )
      end

      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Re-enabling netsuite after reassessment"
        )
      end

      it "re-enables the feature and creates a rollback audit log" do
        result = service.call

        expect(result).to be_success
        expect(organization.reload.premium_integrations).to include("netsuite")

        rollback_log = result.audit_log
        expect(rollback_log.action).to eq("rollback")
        expect(rollback_log.after_value).to be(true)
        expect(rollback_log.before_value).to be(false)
        expect(rollback_log.rollback_of).to eq(original_log)
      end
    end

    context "when rolling back a feature flag toggle_on" do
      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_on,
          organization: organization,
          feature_type: :feature_flag,
          feature_key: "multiple_payment_methods",
          before_value: false,
          after_value: true,
          reason: "Enabling flag for testing purposes"
        )
      end

      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back flag for testing purposes"
        )
      end

      before { organization.enable_feature_flag!("multiple_payment_methods") }

      it "disables the feature flag and creates a rollback audit log" do
        allow(organization).to receive(:disable_feature_flag!).and_call_original

        result = service.call

        expect(result).to be_success
        expect(organization).to have_received(:disable_feature_flag!).with("multiple_payment_methods")

        rollback_log = result.audit_log
        expect(rollback_log.action).to eq("rollback")
        expect(rollback_log.feature_type).to eq("feature_flag")
        expect(rollback_log.feature_key).to eq("multiple_payment_methods")
        expect(rollback_log.after_value).to be(false)
        expect(rollback_log.rollback_of).to eq(original_log)
      end
    end

    context "when audit_log is nil" do
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: nil,
          reason: "This should fail with not found"
        )
      end

      it "returns a not found failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("audit_log")
      end
    end

    context "when rollback succeeds" do
      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_on,
          organization: organization,
          feature_type: :premium_integration,
          feature_key: "okta",
          before_value: false,
          after_value: true,
          reason: "Enabling okta for testing purposes"
        )
      end

      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back okta toggle for testing"
        )
      end

      before { organization.update!(premium_integrations: ["okta"]) }

      it "dispatches a Slack notification job after rollback" do
        result = service.call

        expect(result).to be_success
        expect(Admin::SlackNotificationJob).to have_received(:perform_later).with(result.audit_log.id)
      end
    end
  end
end
