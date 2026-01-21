# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::UpdateService do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:admin_role) { create(:role, :admin) }
  let!(:manager_role) { create(:role, :manager) }
  let(:params) { {roles: %w[manager]} }

  describe "#call" do
    context "when another admin exists" do
      before do
        create(:membership_role, membership:, role: admin_role)
        other_membership = create(:membership, organization:)
        create(:membership_role, membership: other_membership, role: admin_role)
      end

      it "updates the role" do
        result = described_class.call(membership:, params:)

        expect(result).to be_success
        expect(result.membership.roles).to eq([manager_role])
      end
    end

    context "when membership is the last admin" do
      before { create(:membership_role, membership:, role: admin_role) }

      it "returns an error" do
        result = described_class.call(membership:, params:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("last_admin")
      end
    end

    context "when membership is not found" do
      it "returns an error" do
        result = described_class.call(membership: nil, params:)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("membership_not_found")
      end
    end

    context "when role is invalid" do
      before { create(:membership_role, membership:, role: admin_role) }

      let(:params) { {roles: %w[invalid]} }

      it "returns an error" do
        result = described_class.call(membership:, params:)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("role_not_found")
      end
    end
  end
end
