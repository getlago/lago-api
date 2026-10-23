# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ToolGuard do
  subject(:guard) { described_class.new(membership:) }

  let(:organization) { create(:organization) }
  let(:role) { create(:role, organization:, permissions: %w[ai_conversations:create ai_conversations:view customers:view coupons:view]) }
  let(:membership) { create(:membership, organization:, role:) }

  describe "#exposed?" do
    it "only exposes tools of the policy" do
      expect(guard.exposed?("create_coupon")).to be(true)
      expect(guard.exposed?("drop_database")).to be(false)
    end
  end

  describe "#decide" do
    it "runs a read the member's role allows" do
      expect(guard.decide("list_customers")).to be_run
    end

    it "refuses a write the member's role does not allow" do
      decision = guard.decide("create_coupon", {"coupon" => {"code" => "SPRING"}})

      expect(decision).to be_refuse
      expect(decision.message).to include("coupons:create")
    end

    it "refuses a read the member's role does not allow" do
      decision = guard.decide("list_invoices")

      expect(decision).to be_refuse
      expect(decision.message).to include("invoices:view")
    end

    it "refuses a tool missing from the policy" do
      expect(guard.decide("drop_database")).to be_refuse
    end

    context "when the member's role allows the write" do
      let(:role) { create(:role, organization:, permissions: %w[ai_conversations:create coupons:create]) }

      it "asks for the member's confirmation" do
        expect(guard.decide("create_coupon")).to be_confirm
      end
    end

    context "when the member is an admin" do
      let(:membership) { create(:membership, organization:, roles: %w[admin]) }

      it "still asks for the member's confirmation before a write" do
        expect(guard.decide("void_invoice")).to be_confirm
        expect(guard.decide("create_event")).to be_confirm
      end
    end

    context "when the membership is revoked" do
      let(:membership) { create(:membership, :revoked, organization:, roles: %w[admin]) }

      it "refuses every tool" do
        expect(guard.decide("list_customers")).to be_refuse
      end
    end
  end
end
