# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ApplyFeatureChangeService do
  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }
  let(:reason) { "Enable the feature for onboarding" }

  def change_feature(organization:, feature_key: "okta", feature_type: "premium_integration", enabled: true, **options)
    described_class.call(actor:, organization:, feature_key:, feature_type:, enabled:, reason:, **options)
  end

  describe "#call" do
    it "preserves unrelated integrations when the caller holds a stale organization" do
      stale = Organization.find(organization.id)
      organization.update!(premium_integrations: ["netsuite"])

      result = change_feature(organization: stale)

      expect(result).to be_success
      expect(organization.reload.premium_integrations).to match_array(%w[netsuite okta])
      expect(result.audit_log.before_value).to be(false)
    end

    it "preserves unrelated feature flags when the caller holds a stale organization" do
      stale = Organization.find(organization.id)
      organization.enable_feature_flag!("wallet_traceability")

      result = change_feature(organization: stale, feature_type: "feature_flag", feature_key: "order_forms")

      expect(result).to be_success
      expect(organization.reload.feature_flags).to match_array(%w[wallet_traceability order_forms])
    end

    [true, false].each do |enabled|
      context "when the feature is already #{enabled ? "enabled" : "disabled"}" do
        before { organization.update!(premium_integrations: enabled ? ["okta"] : []) }

        it "rejects the no-op without writing an audit log or notifying" do
          expect do
            result = change_feature(organization:, enabled:, notify_org_admin: true)
            expect(result).not_to be_success
            expect(result.error.messages[:enabled]).to eq([enabled ? "feature_already_enabled" : "feature_already_disabled"])
          end.not_to change(CsAdminAuditLog, :count)

          expect(organization.reload.premium_integrations).to eq(enabled ? ["okta"] : [])
          expect(Admin::SlackNotificationJob).not_to have_been_enqueued
          expect(SendEmailJob).not_to have_been_enqueued
        end
      end
    end

    it "validates feature types before writing" do
      result = change_feature(organization:, feature_type: "organization")

      expect(result.error.messages[:feature_type]).to eq(["invalid"])
      expect(organization.reload.premium_integrations).to eq([])
    end

    it "validates unknown feature flags before writing" do
      result = change_feature(organization:, feature_type: "feature_flag", feature_key: "removed_flag")

      expect(result.error.messages[:feature_key]).to eq(["invalid"])
      expect(organization.reload.feature_flags).to eq([])
    end

    it "validates boolean values for service callers" do
      result = change_feature(organization:, enabled: "false")

      expect(result.error.messages[:enabled]).to eq(["invalid_boolean"])
      expect(organization.reload.premium_integrations).to eq([])
    end

    [nil, "", "short", "x" * 501].each do |invalid_reason|
      context "with invalid reason #{invalid_reason.inspect.truncate(30)}" do
        let(:reason) { invalid_reason }

        it "leaves the feature, audit trail and notifications unchanged" do
          expect do
            result = change_feature(organization:, notify_org_admin: true)
            expect(result).not_to be_success
            expect(result.error.messages).to have_key(:reason)
          end.not_to change(CsAdminAuditLog, :count)

          expect(organization.reload.premium_integrations).to eq([])
          expect(Admin::SlackNotificationJob).not_to have_been_enqueued
          expect(SendEmailJob).not_to have_been_enqueued
        end
      end
    end

    it "does not enqueue notifications when an outer transaction rolls back" do
      organization
      actor
      ActiveRecord::Base.transaction(requires_new: true) do
        expect(change_feature(organization:, notify_org_admin: true)).to be_success
        raise ActiveRecord::Rollback
      end

      expect(organization.reload.premium_integrations).to eq([])
      expect(CsAdminAuditLog.count).to eq(0)
      expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      expect(SendEmailJob).not_to have_been_enqueued
    end

    context "with concurrent requests", transaction: false do
      it "retains both changes and their audit records" do
        actor
        org_id = organization.id
        ready = Queue.new
        start = Queue.new
        threads = %w[okta netsuite].map do |key|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              org = Organization.find(org_id)
              ready << true
              start.pop
              change_feature(organization: org, feature_key: key)
            end
          end
        end

        Timeout.timeout(10) { 2.times { ready.pop } }
        2.times { start << true }
        results = Timeout.timeout(10) { threads.map(&:value) }

        expect(results).to all(be_success)
        expect(organization.reload.premium_integrations).to match_array(%w[okta netsuite])
        expect(CsAdminAuditLog.where(organization:).pluck(:feature_key)).to match_array(%w[okta netsuite])
      ensure
        threads&.each { |thread| thread.kill if thread.alive? }
      end
    end
  end
end
