# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::UpdateService do
  subject(:result) { described_class.call(user: acting_user, invite:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:acting_user) { create(:membership, organization:).user }
  let(:invite) { create(:invite, organization:) }
  let(:params) { {roles: %w[manager]} }

  describe "#call" do
    context "when invite is pending" do
      let(:acting_user) { create(:membership, organization:, roles: %i[admin]).user }
      let(:invite) { create(:invite, organization:, status: "pending", roles: %w[admin]) }
      let(:params) { {roles: %w[manager]} }

      before { create(:role, :manager) }

      it "updates the roles" do
        expect(result).to be_success
        expect(result.invite.reload.roles).to eq(%w[manager])
      end
    end

    context "when non-admin sets admin role on invite" do
      let(:invite) { create(:invite, organization:, status: "pending", roles: %w[manager]) }
      let(:params) { {roles: %w[admin]} }

      before { create(:role, :admin) }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("cannot_grant_admin")
      end
    end

    context "when admin sets admin role on invite" do
      let(:acting_membership) { create(:membership, organization:) }
      let(:acting_user) { acting_membership.user }
      let(:admin_role) { create(:role, :admin) }
      let(:invite) { create(:invite, organization:, status: "pending", roles: %w[manager]) }
      let(:params) { {roles: %w[admin]} }

      before { create(:membership_role, membership: acting_membership, role: admin_role) }

      it "updates the roles" do
        expect(result).to be_success
        expect(result.invite.reload.roles).to eq(%w[admin])
      end
    end

    context "when non-admin adds a role holding permissions they do not hold" do
      let(:acting_user) { create(:membership, organization:, roles: %i[finance]).user }
      let(:custom_role) { create(:role, :custom, organization:, permissions: %w[developers:keys:manage]) }
      let(:invite) { create(:invite, organization:, status: "pending", roles: %w[finance]) }
      let(:params) { {roles: ["finance", custom_role.code]} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("cannot_grant_permissions")
        expect(invite.reload.roles).to eq(%w[finance])
      end
    end

    context "when non-admin keeps a role they do not hold and removes another" do
      let(:acting_user) { create(:membership, organization:, roles: %i[finance]).user }
      let(:custom_role) { create(:role, :custom, organization:, permissions: %w[developers:keys:manage]) }
      let(:invite) { create(:invite, organization:, status: "pending", roles: ["finance", custom_role.code]) }
      let(:params) { {roles: [custom_role.code]} }

      it "updates the roles" do
        expect(result).to be_success
        expect(invite.reload.roles).to eq([custom_role.code])
      end
    end

    context "when invite is not found" do
      let(:invite) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when invite is revoked" do
      let(:invite) { create(:invite, organization:, status: "revoked") }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("cannot_update_revoked_invite")
      end
    end

    context "when invite is accepted" do
      let(:invite) { create(:invite, organization:, status: "accepted") }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("cannot_update_accepted_invite")
      end
    end

    context "when roles are empty" do
      let(:invite) { create(:invite, organization:, status: "pending") }
      let(:params) { {roles: []} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end
    end

    context "when roles do not exist" do
      let(:invite) { create(:invite, organization:, status: "pending") }
      let(:params) { {roles: %w[nonexistent_role]} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end
    end
  end
end
