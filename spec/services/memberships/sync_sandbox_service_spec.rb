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

    it "changes nothing the second time, and keeps the keys the AI agent holds for the sandbox member" do
      described_class.call!(organization: production, user:, actor:)
      api_key = ApiKeys::CreateMemberKeyService.call!(membership: sandbox_membership).api_key

      expect { result }.not_to change { sandbox.memberships.count + MembershipRole.count }
      expect(security_logger).to have_received(:produce).once
      expect(ApiKey.unscoped.find(api_key.id)).not_to be_expired
    end
  end

  context "when the user's roles changed on production" do
    let(:agent_key) { ApiKeys::CreateMemberKeyService.call!(membership: sandbox_membership).api_key }

    before do
      create(:membership, user:, organization: production, roles: %i[admin])
      create(:membership, user:, organization: sandbox, roles: %i[finance])
      agent_key
    end

    it "gives the sandbox membership the same roles" do
      expect(result.sandbox_membership.roles.reload).to eq([admin])
      removed_links = MembershipRole.with_discarded.discarded.where(membership: result.sandbox_membership).to_a
      expect(removed_links.size).to eq(1)
      expect(removed_links.map(&:updated_at)).to eq(removed_links.map(&:deleted_at))
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "user",
        log_event: "user.role_edited", user: actor, resources: {email: user.email, roles: {added: ["admin"], deleted: ["finance"]}})
    end

    it "expires the keys the AI agent holds for the sandbox member" do
      result

      expect(ApiKey.unscoped.find(agent_key.id)).to be_expired
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
    let(:agent_key) { ApiKeys::CreateMemberKeyService.call!(membership: sandbox_membership).api_key }

    before do
      create(:membership, :revoked, user:, organization: production)
      create(:membership, user:, organization: sandbox, roles: %i[admin])
      agent_key
    end

    it "revokes the sandbox membership, even when it holds the sandbox's last admin role" do
      result

      expect(sandbox_membership).to be_nil
      expect(security_logger).to have_received(:produce).with(organization: sandbox, log_type: "user",
        log_event: "user.deleted", user: actor, resources: {email: user.email})
    end

    it "expires the keys the AI agent holds for the sandbox member" do
      result

      expect(ApiKey.unscoped.find(agent_key.id)).to be_expired
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
