# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::SyncSandboxService do
  subject(:result) { described_class.call(organization: production, user:, actor:) }

  include_context "with mocked security logger"

  let(:production) { create(:organization, :with_sandbox) }
  let(:sandbox) { production.sandbox_organization }
  let(:user) { create(:user) }
  let(:actor) { create(:user) }
  let(:finance) { create(:role, :finance) }
  let(:admin) { create(:role, :admin) }

  def sandbox_membership
    sandbox.memberships.active.find_by(user:)
  end

  context "when the user joined the production organization" do
    before { create(:membership, user:, organization: production, roles: %i[finance]) }

    it "adds them to the sandbox with the same roles, logged with the production actor" do
      expect(result.sandbox_membership).to eq(sandbox_membership)
      expect(sandbox_membership.roles).to eq([finance])
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "user",
        log_event: "user.added", user: actor, resources: {email: user.email, roles: ["finance"]})
    end

    it "changes nothing the second time" do
      described_class.call!(organization: production, user:, actor:)

      expect { result }.not_to change { sandbox.memberships.count + MembershipRole.count }
      expect(security_logger).to have_received(:produce).once
    end
  end

  context "when the user's roles changed on production" do
    before do
      create(:membership, user:, organization: production, roles: %i[admin])
      create(:membership, user:, organization: sandbox, roles: %i[finance])
    end

    it "gives the sandbox membership the same roles" do
      expect(result.sandbox_membership.roles.reload).to eq([admin])
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "user",
        log_event: "user.role_edited", user: actor, resources: {email: user.email, roles: {added: ["admin"], deleted: ["finance"]}})
    end
  end

  context "with a custom role" do
    let(:custom) { create(:role, organization: production, code: "auditor", name: "Auditor", permissions: %w[organization:view]) }

    before { create(:membership, user:, organization: production, role: custom) }

    it "grants the sandbox copy of the role" do
      copy = sandbox_membership_role_after(result)

      expect(copy).to have_attributes(organization_id: sandbox.id, code: "auditor", name: "Auditor",
        permissions: %w[organization:view])
    end

    def sandbox_membership_role_after(result)
      result.sandbox_membership.roles.sole
    end

    context "when the sandbox copy exists" do
      let(:copy) { create(:role, organization: sandbox, code: "auditor", name: "Auditor", permissions: %w[organization:view]) }

      before do
        copy
        allow(Roles::SyncSandboxService).to receive(:call!).and_call_original
      end

      it "grants it without syncing the role again" do
        expect(sandbox_membership_role_after(result)).to eq(copy)
        expect(Roles::SyncSandboxService).not_to have_received(:call!)
      end
    end
  end

  context "when the production membership was revoked" do
    before do
      create(:membership, :revoked, user:, organization: production)
      create(:membership, user:, organization: sandbox, roles: %i[admin])
    end

    it "revokes the sandbox membership, even when it holds the sandbox's last admin role" do
      result

      expect(sandbox_membership).to be_nil
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "user",
        log_event: "user.deleted", user: actor, resources: {email: user.email})
    end
  end

  context "without a sandbox" do
    let(:production) { create(:organization) }

    before { create(:membership, user:, organization: production) }

    it "does nothing" do
      expect { result }.not_to change(Membership, :count)
      expect(result.sandbox_membership).to be_nil
    end
  end

  context "with a sandbox organization" do
    subject(:result) { described_class.call(organization: sandbox, user:) }

    it "does nothing" do
      expect { result }.not_to change(Membership, :count)
    end
  end
end
