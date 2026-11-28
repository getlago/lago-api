# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ActivateOrganizationService do
  subject(:result) { described_class.call(actor:, organization:, reason:) }

  include_context "with mocked security logger"

  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }
  let(:reason) { "Opened for a sales prospect" }

  it "opens the organization and audits it with the actor and the reason" do
    expect(result).to be_success
    expect(result.organization).to eq(organization)
    expect(organization.reload.activation_status).to eq("active")

    expect(CsAdminAuditLog.where(organization:).pluck(:action, :actor_user_id, :actor_email, :feature_type,
      :feature_key, :before_value, :after_value, :reason))
      .to eq([["organization_activated", actor.id, "cs@getlago.com", "organization", organization.id, false, true,
        reason]])
  end

  it "notifies Slack once, after commit" do
    expect { result }.to have_enqueued_job_after_commit(Admin::SlackNotificationJob)
  end

  it "produces the security log of the activation, naming the actor" do
    result

    expect(security_logger).to have_received(:produce).once.with(
      hash_including(log_event: "organization.activated", user: actor,
        resources: {activated_by: "cs_admin", reason:})
    )
  end

  context "with an active organization" do
    let(:organization) { create(:organization, :self_serve) }

    it "succeeds without an audit row, a notification or a security log" do
      expect { result }.not_to have_enqueued_job(Admin::SlackNotificationJob)

      expect(result).to be_success
      expect(result.organization).to eq(organization)
      expect(CsAdminAuditLog.where(organization:)).to be_empty
      expect(security_logger).not_to have_received(:produce)
    end
  end

  context "with an organization that is not self-serve" do
    let(:organization) { create(:organization) }

    it "refuses it and writes nothing" do
      expect(result).to be_failure
      expect(result.error.code).to eq("organization_not_self_serve_production")
      expect(CsAdminAuditLog.where(organization:)).to be_empty
      expect(security_logger).not_to have_received(:produce)
    end
  end

  context "with a sandbox" do
    let(:organization) do
      create(:organization, :self_serve, :sandbox, production_organization: create(:organization, :self_serve))
    end

    it "refuses it" do
      expect(result.error.code).to eq("organization_not_self_serve_production")
      expect(CsAdminAuditLog.where(organization:)).to be_empty
    end
  end

  context "without an organization" do
    let(:organization) { nil }

    it "answers not found" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("organization")
    end
  end

  context "with a reason that is too short" do
    let(:reason) { "short" }

    it "refuses it before activating anything" do
      expect(result.error.messages).to eq(reason: ["value_is_too_short"])
      expect(organization.reload.activation_status).to eq("pending_payment_method")
      expect(CsAdminAuditLog.where(organization:)).to be_empty
    end
  end
end
