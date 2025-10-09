# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::UpdateService do
  let(:membership) { create(:membership, role: "admin") }
  let(:organization) { membership.organization }
  let(:params) { {role: "manager"} }

  describe "#call" do
    context "when another admin exists" do
      it "update the role" do
        create(:membership, organization: organization, role: "admin")

        result = described_class.call(membership:, params:)

        expect(result).to be_success
        expect(result.membership.reload.role).to eq("manager")
      end
    end

    context "when membership is the last admin" do
      it "returns an error" do
        result = described_class.call(membership:, params:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("last_admin")
      end
    end

    context "when membership is not found" do
      let(:membership) { nil }

      it "returns an error" do
        result = described_class.call(membership:, params:)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("membership_not_found")
      end
    end
  end
end
