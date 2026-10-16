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
  let(:feature_flags) { ["order_forms"] }
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
      expect(organization.reload.default_billing_entity.document_numbering).to eq("per_billing_entity")
    end

    context "when a timezone is provided", :premium do
      let(:timezone) { "Europe/Paris" }

      it "sets the timezone on the organization" do
        result = service.call

        expect(result.organization.reload.timezone).to eq("Europe/Paris")
      end
    end

    it "sets premium integrations on the organization" do
      result = service.call

      expect(result.organization.premium_integrations).to match_array(["okta", "netsuite"])
    end

    it "sets feature flags on the organization" do
      result = service.call

      expect(result.organization.reload.feature_flags).to include("order_forms")
    end

    it "creates an invite for the owner email and returns the invite url" do
      result = service.call
      organization = result.organization

      invite = Invite.find_by(organization: organization, email: owner_email)
      expect(invite).to be_present
      expect(result.invite_url).to include("/invitation/#{invite.token}")
    end

    it "creates audit logs for the organization, premium integrations and feature flags" do
      result = service.call
      organization = result.organization

      logs = CsAdminAuditLog.where(organization:)
      expect(logs.count).to eq(4)
      expect(logs.pluck(:action).uniq).to eq(["org_created"])
      expect(logs.pluck(:batch_id).uniq.count).to eq(1)

      organization_logs = logs.where(feature_type: "organization")
      expect(organization_logs.pluck(:feature_key)).to eq(["organization"])

      integration_logs = logs.where(feature_type: "premium_integration")
      expect(integration_logs.pluck(:feature_key)).to match_array(["okta", "netsuite"])

      flag_logs = logs.where(feature_type: "feature_flag")
      expect(flag_logs.pluck(:feature_key)).to eq(["order_forms"])

      logs.each do |log|
        expect(log.actor_user).to eq(actor)
        expect(log.actor_email).to eq("cs@getlago.com")
        expect(log.before_value).to eq((log.feature_type == "organization") ? nil : false)
        expect(log.after_value).to be(true)
        expect(log.reason).to eq("New enterprise customer onboarding")
      end
    end

    it "enqueues a Slack notification job for each audit log" do
      result = service.call
      organization = result.organization

      log_ids = CsAdminAuditLog.where(organization:).pluck(:id)
      expect(log_ids.count).to eq(4)

      log_ids.each do |log_id|
        expect(Admin::SlackNotificationJob).to have_been_enqueued.with(log_id)
      end
    end

    context "when the owner email is invalid" do
      let(:owner_email) { "not-an-email" }

      it "returns a validation failure without creating anything" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to include(email: ["invalid_email_format"])
      end

      it "does not persist the organization, the invite nor the audit logs" do
        expect { service.call }.not_to change(Organization, :count)

        expect(Invite.count).to eq(0)
        expect(CsAdminAuditLog.count).to eq(0)
        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end

    context "when a feature flag is unknown" do
      let(:feature_flags) { ["order_forms", "not_a_real_flag"] }

      it "returns a validation failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:feature_flags]).to eq(["invalid"])
      end

      it "does not persist anything" do
        expect { service.call }.not_to change(Organization, :count)

        expect(Invite.count).to eq(0)
        expect(CsAdminAuditLog.count).to eq(0)
        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
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

      it "creates an audit log for the organization creation" do
        result = service.call

        expect(result).to be_success

        logs = CsAdminAuditLog.where(organization: result.organization)
        expect(logs.count).to eq(1)

        log = logs.sole
        expect(log.action).to eq("org_created")
        expect(log.feature_type).to eq("organization")
        expect(log.feature_key).to eq("organization")
        expect(log.before_value).to eq((log.feature_type == "organization") ? nil : false)
        expect(log.after_value).to be(true)
        expect(Admin::SlackNotificationJob).to have_been_enqueued.with(log.id)
      end
    end

    context "with duplicate feature inputs" do
      let(:premium_integrations) { %w[okta okta] }
      let(:feature_flags) { %w[order_forms order_forms] }

      it "creates one grant and audit record per feature" do
        result = service.call

        expect(result).to be_success
        expect(result.organization.premium_integrations).to eq(["okta"])
        expect(result.organization.feature_flags).to eq(["order_forms"])
        expect(CsAdminAuditLog.where(organization: result.organization).pluck(:feature_key))
          .to match_array(%w[organization okta order_forms])
      end
    end

    context "with invalid premium integrations" do
      let(:premium_integrations) { ["invalid_integration"] }

      it "does not persist an organization, invite or audit record" do
        expect { service.call }.not_to change(Organization, :count)

        expect(Invite.count).to eq(0)
        expect(CsAdminAuditLog.count).to eq(0)
        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end

    context "with an invalid reason" do
      let(:reason) { "short" }

      it "rolls back creation and suppresses notifications" do
        expect { service.call }.not_to change(Organization, :count)

        expect(Invite.count).to eq(0)
        expect(CsAdminAuditLog.count).to eq(0)
        expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      end
    end

    it "does not notify Slack if the outer transaction rolls back" do
      actor
      ActiveRecord::Base.transaction(requires_new: true) do
        expect(service.call).to be_success
        raise ActiveRecord::Rollback
      end

      expect(Organization.count).to eq(0)
      expect(Invite.count).to eq(0)
      expect(CsAdminAuditLog.count).to eq(0)
      expect(Admin::SlackNotificationJob).not_to have_been_enqueued
    end

    context "with security logging enabled", :premium, transaction: false do
      include_context "with security log infrastructure"

      let(:premium_integrations) { ["security_logs"] }
      let(:security_events) { [] }

      before do
        allow(Utils::KafkaProducer).to receive(:produce_async) do |topic:, payload:, **|
          security_events << JSON.parse(payload) if topic == kafka_security_logs_topic
        end
      end

      it "publishes both security events only after the outer transaction commits" do
        result = nil
        ActiveRecord::Base.transaction do
          result = service.call

          expect(result).to be_success
          expect(security_events).to eq([])
        end

        expect(security_events.map { |event| event.slice("organization_id", "log_event", "resources") }).to match_array([
          {
            "organization_id" => result.organization.id,
            "log_event" => "billing_entity.created",
            "resources" => {"billing_entity_name" => name, "billing_entity_code" => "hooli_inc"}
          },
          {
            "organization_id" => result.organization.id,
            "log_event" => "user.invited",
            "resources" => {"invitee_email" => owner_email}
          }
        ])
      end

      context "with an invalid reason" do
        let(:reason) { "short" }

        it "does not publish security events for rolled-back records" do
          expect(service.call).not_to be_success

          expect(Organization.count).to eq(0)
          expect(Invite.count).to eq(0)
          expect(security_events).to eq([])
        end
      end

      context "with an invalid owner email" do
        let(:owner_email) { "not-an-email" }

        it "does not publish the rolled-back billing entity event" do
          expect(service.call).not_to be_success

          expect(Organization.count).to eq(0)
          expect(security_events).to eq([])
        end
      end

      it "does not publish security events when the caller rolls back" do
        ActiveRecord::Base.transaction do
          expect(service.call).to be_success
          raise ActiveRecord::Rollback
        end

        expect(Organization.count).to eq(0)
        expect(Invite.count).to eq(0)
        expect(security_events).to eq([])
      end
    end
  end
end
