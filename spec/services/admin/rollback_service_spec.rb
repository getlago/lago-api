# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::RollbackService do
  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }

  describe "#call" do
    context "when rolling back a toggle_on (disabling the feature)" do
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back okta toggle for testing"
        )
      end

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
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Re-enabling netsuite after reassessment"
        )
      end

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
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back flag for testing purposes"
        )
      end

      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_on,
          organization: organization,
          feature_type: :feature_flag,
          feature_key: "order_forms",
          before_value: false,
          after_value: true,
          reason: "Enabling flag for testing purposes"
        )
      end

      before { organization.enable_feature_flag!("order_forms") }

      it "disables the feature flag and creates a rollback audit log" do
        allow(organization).to receive(:disable_feature_flag!).and_call_original

        result = service.call

        expect(result).to be_success
        expect(organization).to have_received(:disable_feature_flag!).with("order_forms")

        rollback_log = result.audit_log
        expect(rollback_log.action).to eq("rollback")
        expect(rollback_log.feature_type).to eq("feature_flag")
        expect(rollback_log.feature_key).to eq("order_forms")
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

    context "when the audit log is an organization creation" do
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Trying to roll back an organization creation"
        )
      end

      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :org_created,
          organization: organization,
          feature_type: :organization,
          feature_key: "organization",
          before_value: nil,
          after_value: true,
          reason: "Creating the organization for onboarding"
        )
      end

      it "returns a validation failure without touching the organization" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:feature_type]).to eq(["cannot_rollback_organization_creation"])
      end

      it "does not create a rollback audit log nor notify Slack" do
        original_log

        expect { service.call }.not_to change(CsAdminAuditLog, :count)

        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end

    context "when the audit log was already rolled back" do
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Trying to roll back the same change twice"
        )
      end

      let(:original_log) do
        create(
          :cs_admin_audit_log,
          actor_user: actor,
          action: :toggle_on,
          organization: organization,
          feature_type: :premium_integration,
          feature_key: "okta"
        )
      end

      before do
        create(
          :cs_admin_audit_log,
          action: :rollback,
          organization: organization,
          rollback_of: original_log,
          feature_type: :premium_integration,
          feature_key: "okta"
        )
      end

      it "returns a validation failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:audit_log]).to eq(["already_rolled_back"])
      end

      it "does not create another rollback audit log nor notify Slack" do
        expect { service.call }.not_to change(CsAdminAuditLog, :count)

        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end

    context "when rollback succeeds" do
      subject(:service) do
        described_class.new(
          actor: actor,
          audit_log: original_log,
          reason: "Rolling back okta toggle for testing"
        )
      end

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

      before { organization.update!(premium_integrations: ["okta"]) }

      it "dispatches a Slack notification job after rollback" do
        result = service.call

        expect(result).to be_success
        expect(Admin::SlackNotificationJob).to have_been_enqueued.with(result.audit_log.id)
      end
    end
  end

  describe "rollback safeguards" do
    let(:original_log) do
      create(:cs_admin_audit_log, actor_user: actor, organization:,
        feature_key: "okta", before_value: false, after_value: true)
    end

    before { organization.update!(premium_integrations: ["okta"]) }

    def rollback(log = original_log)
      described_class.call(actor:, audit_log: log, reason: "Restore the previous feature state")
    end

    it "rechecks rollback status even when the association was cached as empty" do
      first = original_log
      second = CsAdminAuditLog.find(first.id)
      expect(first.rolled_back?).to be(false)
      expect(second.rolled_back?).to be(false)

      expect(rollback(first)).to be_success
      result = rollback(second)

      expect(result.error.messages[:audit_log]).to eq(["already_rolled_back"])
      expect(CsAdminAuditLog.where(rollback_of_id: first.id).count).to eq(1)
    end

    it "preserves unrelated changes when the original log has a stale organization" do
      original_log.organization
      Organization.find(organization.id).update!(premium_integrations: %w[okta netsuite])

      expect(rollback).to be_success
      expect(organization.reload.premium_integrations).to eq(["netsuite"])
    end

    it "rejects an older change even when a newer off/on cycle restores the same value" do
      original_log.update!(created_at: 2.days.ago)
      create(:cs_admin_audit_log, organization:, feature_key: "okta",
        action: :toggle_off, before_value: true, after_value: false, created_at: 1.day.ago)
      create(:cs_admin_audit_log, organization:, feature_key: "okta",
        action: :toggle_on, before_value: false, after_value: true)

      expect(rollback.error.messages[:audit_log]).to eq(["change_has_been_superseded"])
      expect(organization.reload.premium_integrations).to eq(["okta"])
    end

    it "rejects ambiguous changes with the same timestamp" do
      create(:cs_admin_audit_log, organization:, feature_key: "okta", created_at: original_log.created_at)

      expect(rollback.error.messages[:audit_log]).to eq(["change_has_been_superseded"])
      expect(organization.reload.premium_integrations).to eq(["okta"])
    end

    it "rejects a feature whose state changed outside the panel" do
      original_log
      organization.update!(premium_integrations: [])

      expect(rollback.error.messages[:audit_log]).to eq(["change_has_been_superseded"])
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
    end

    it "does not let a legacy no-op entry disable an existing feature" do
      original_log.update!(before_value: true)

      expect(rollback).not_to be_success
      expect(organization.reload.premium_integrations).to eq(["okta"])
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
    end

    it "rejects rollback of a rollback" do
      reverted = rollback.audit_log

      expect(rollback(reverted).error.messages[:audit_log]).to eq(["cannot_rollback_a_rollback"])
      expect(organization.reload.premium_integrations).to eq([])
    end

    it "restores creation-time grants with legacy nil before values to disabled" do
      original_log.update!(action: :org_created, before_value: nil)

      result = rollback

      expect(result).to be_success
      expect(result.audit_log.after_value).to be(false)
      expect(organization.reload.premium_integrations).to eq([])
    end

    it "rejects retired feature keys with a validation error" do
      original_log.update!(feature_type: :feature_flag, feature_key: "retired_flag")

      expect(rollback.error.messages[:feature_key]).to eq(["feature_no_longer_available"])
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
      expect(Admin::SlackNotificationJob).not_to have_been_enqueued
    end

    it "does not enqueue notifications when an outer transaction rolls back" do
      original_log
      ActiveRecord::Base.transaction(requires_new: true) do
        expect(rollback).to be_success
        raise ActiveRecord::Rollback
      end

      expect(organization.reload.premium_integrations).to eq(["okta"])
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
      expect(Admin::SlackNotificationJob).not_to have_been_enqueued
    end
  end
end
