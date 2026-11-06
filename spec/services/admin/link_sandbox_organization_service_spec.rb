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

  context "with a reason that is too short" do
    let(:reason) { "short" }

    it "rolls the link back" do
      expect(result.error.messages).to eq(reason: ["value_is_too_short"])
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
