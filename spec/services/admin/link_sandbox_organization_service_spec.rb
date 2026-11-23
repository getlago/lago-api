# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::LinkSandboxOrganizationService do
  subject(:result) do
    described_class.call(actor:, production_organization: production, sandbox_organization: target, reason:)
  end

  include_context "with self-serve enabled"

  let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:production) { create(:organization) }
  let(:target) { create(:organization) }
  let(:reason) { "Linking the customer's test organization" }

  it "links the sandbox and audits it on both organizations, in one batch" do
    expect(result).to be_success

    rows = CsAdminAuditLog.where(action: :sandbox_linked).pluck(:organization_id, :feature_key, :batch_id)
    expect(rows.map { it.first(2) }).to match_array([[target.id, production.id], [production.id, target.id]])
    expect(rows.map(&:last).uniq.size).to eq(1)
  end

  it "notifies Slack once, after commit" do
    expect { result }.to have_enqueued_job_after_commit(Admin::SlackNotificationJob)
  end

  context "when production has premium integrations and feature flags" do
    let(:production) { create(:organization, premium_integrations: ["netsuite"], feature_flags: ["order_forms"]) }

    it "audits each feature the sandbox copied, in the batch of the link" do
      expect(result).to be_success

      batch_id = CsAdminAuditLog.find_by!(organization: target, action: :sandbox_linked).batch_id
      expect(CsAdminAuditLog.where(organization: target, action: :toggle_on)
        .pluck(:feature_type, :feature_key, :before_value, :after_value, :reason, :batch_id))
        .to match_array([
          ["premium_integration", "netsuite", false, true, reason, batch_id],
          ["feature_flag", "order_forms", false, true, reason, batch_id]
        ])
    end
  end

  context "with a reason that is too short" do
    let(:reason) { "short" }

    before { allow(Organizations::LinkSandboxService).to receive(:call!).and_call_original }

    it "refuses it before linking anything" do
      expect(result.error.messages).to eq(reason: ["value_is_too_short"])
      expect(Organizations::LinkSandboxService).not_to have_received(:call!)
      expect(target.reload).to be_production
    end
  end

  context "when the link is refused" do
    before { create(:membership, organization: target) }

    it "writes no audit row" do
      expect(result.error.code).to eq("sandbox_has_other_members")
      expect(CsAdminAuditLog.count).to eq(0)
    end
  end
end
