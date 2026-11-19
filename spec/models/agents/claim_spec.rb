# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Claim do
  subject(:claim) { build(:agent_claim) }

  describe "enums" do
    it do
      expect(claim).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(issued: "issued", started: "started", verified: "verified")
    end
  end

  describe "associations" do
    it do
      expect(claim).to belong_to(:organization)
      expect(claim).to belong_to(:registration).class_name("Agents::Registration")
    end
  end

  describe "Scopes" do
    describe ".live" do
      it "returns the claims that can still be used" do
        issued = create(:agent_claim)
        started = create(:agent_claim, :started)
        create(:agent_claim, :verified)

        expect(described_class.live).to match_array([issued, started])
      end
    end
  end

  describe "validations" do
    it do
      expect(claim).to validate_presence_of(:code_hash)
    end
  end

  describe ".normalize_code" do
    it "ignores case and separators" do
      expect(described_class.normalize_code(" abcd-2345 ")).to eq("ABCD2345")
      expect(described_class.normalize_code(nil)).to eq("")
    end
  end

  describe ".for_code" do
    let!(:stored) { create(:agent_claim, code: "ABCD2345") }

    it "finds the claim by the digest of the normalized code" do
      expect(described_class.for_code("abcd 2345")).to eq(stored)
      expect(described_class.for_code("ABCD234")).to be_nil
      expect(described_class.for_code("ABCD2346")).to be_nil
    end
  end

  describe ".generate_code and .format_code" do
    it "draws 8 characters without 0, O, 1 or I, shown in two groups" do
      code = described_class.generate_code

      expect(code).to match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}\z/)
      expect(described_class.format_code("ABCD2345")).to eq("ABCD-2345")
    end
  end

  describe "#public_status" do
    it "names the three statuses the way the agent reads them" do
      expect(build(:agent_claim).public_status).to eq("unclaimed")
      expect(build(:agent_claim, :started).public_status).to eq("pending")
      expect(build(:agent_claim, :verified).public_status).to eq("claimed")
    end
  end

  describe "#verification_expired?" do
    it "is derived from the time, and false before a code is issued" do
      freeze_time do
        expect(build(:agent_claim, verification_expires_at: nil)).not_to be_verification_expired
        expect(build(:agent_claim, verification_expires_at: 1.second.from_now)).not_to be_verification_expired
        expect(build(:agent_claim, verification_expires_at: Time.current)).to be_verification_expired
      end
    end
  end
end
