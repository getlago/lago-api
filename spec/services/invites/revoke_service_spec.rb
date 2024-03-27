# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::RevokeService, type: :service do
  subject(:revoke_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:) }

  describe "#call" do
    context "when invite is not found" do
      let(:revoke_args) do
        {
          id: nil,
          current_organization: organization
        }
      end

      it "returns an error" do
        result = revoke_service.call(**revoke_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when invite is revoked" do
      let(:revoked_invite) { create(:invite, organization:, status: "revoked") }
      let(:revoke_args) do
        {
          id: revoked_invite.id,
          current_organization: organization
        }
      end

      it "returns an error" do
        result = revoke_service.call(**revoke_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when invite is accepted" do
      let(:accepted_invite) { create(:invite, organization:, status: "accepted") }
      let(:revoke_args) do
        {
          id: accepted_invite.id,
          current_organization: organization
        }
      end

      it "returns an error" do
        result = revoke_service.call(**revoke_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when revoking invite" do
      let(:revoke_args) do
        {
          id: invite.id,
          current_organization: organization
        }
      end

      it "revokes the invite" do
        freeze_time do
          result = revoke_service.call(**revoke_args)

          expect(result).to be_success
          expect(result.invite.id).to eq(invite.id)
          expect(result.invite).to be_revoked
          expect(result.invite.revoked_at).to eq(Time.current)
        end
      end
    end
  end
end
