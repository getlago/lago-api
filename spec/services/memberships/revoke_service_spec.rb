# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::RevokeService do
  subject(:revoke_service) { described_class.new(user:, membership:) }

  let(:organization) { create(:organization) }

  let(:user) { create(:user) }
  let(:membership) { create(:membership, organization:) }
  let(:other_membership) { create(:membership, user:, organization:, role: :admin) }

  before { other_membership }

  describe "#call" do
    context "when revoking my own membership" do
      let(:membership) { create(:membership, user:, organization:) }
      let(:other_membership) { create(:membership, organization:, role: :admin) }

      it "returns an error" do
        result = revoke_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("cannot_revoke_own_membership")
      end
    end

    context "when membership is not found" do
      let(:membership) { nil }

      it "returns an error" do
        result = revoke_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("membership_not_found")
      end
    end

    context "when revoking another membership" do
      it "revokes the membership" do
        freeze_time do
          result = revoke_service.call

          expect(result).to be_success
          expect(result.membership.id).to eq(membership.id)
          expect(result.membership.status).to eq("revoked")
          expect(result.membership.revoked_at).to eq(Time.current)
        end
      end
    end

    context "when removing the last admin" do
      let(:membership) { create(:membership, organization:, role: :admin) }
      let(:other_membership) { create(:membership, user:, organization:, role: :finance) }

      it "returns an error" do
        result = revoke_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("last_admin")
      end
    end
  end
end
