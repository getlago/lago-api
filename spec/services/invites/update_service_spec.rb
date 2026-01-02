# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::UpdateService do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:) }
  let(:params) { {roles: %w[manager]} }

  describe "#call" do
    context "when invite is pending" do
      let(:invite) { create(:invite, organization:, status: "pending", roles: %w[admin]) }
      let(:params) { {roles: %w[manager]} }

      before { create(:role, :manager) }

      it "updates the roles" do
        result = described_class.call(invite:, params:)

        expect(result).to be_success
        expect(result.invite.reload.roles).to eq(%w[manager])
      end
    end

    context "when invite is not found" do
      let(:invite) { nil }

      it "returns an error" do
        result = described_class.call(invite:, params:)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when invite is revoked" do
      let(:invite) { create(:invite, organization:, status: "revoked") }

      it "returns an error" do
        result = described_class.call(invite:, params:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("cannot_update_revoked_invite")
      end
    end

    context "when invite is accepted" do
      let(:invite) { create(:invite, organization:, status: "accepted") }

      it "returns an error" do
        result = described_class.call(invite:, params:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("cannot_update_accepted_invite")
      end
    end

    context "when roles are empty" do
      let(:invite) { create(:invite, organization:, status: "pending") }
      let(:params) { {roles: []} }

      it "returns an error" do
        result = described_class.call(invite:, params:)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end
    end

    context "when roles do not exist" do
      let(:invite) { create(:invite, organization:, status: "pending") }
      let(:params) { {roles: %w[nonexistent_role]} }

      it "returns an error" do
        result = described_class.call(invite:, params:)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end
    end
  end
end
