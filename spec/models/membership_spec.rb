# frozen_string_literal: true

require "rails_helper"

RSpec.describe Membership do
  subject(:membership) { create(:membership) }

  it { is_expected.to have_many(:data_exports) }
  it { is_expected.to have_many(:membership_roles) }
  it { is_expected.to have_many(:roles).through(:membership_roles) }

  it_behaves_like "paper_trail traceable"

  describe "#admin?" do
    it "returns true when membership role is admin" do
      membership = create(:membership, role: :admin)
      expect(membership.admin?).to be true
    end

    it "returns false when membership role is not admin" do
      membership = create(:membership, role: :finance)
      expect(membership.admin?).to be false
    end
  end

  describe "#mark_as_revoked" do
    it "revokes the membership with a Time" do
      freeze_time do
        expect { membership.mark_as_revoked! }
          .to change { membership.reload.status }.from("active").to("revoked")
          .and change(membership, :revoked_at).from(nil).to(Time.current)
      end
    end
  end

  describe "#permissions_hash" do
    subject(:permissions_hash) { membership.permissions_hash }

    context "with admin role" do
      let(:membership) { create(:membership, role: :admin) }

      it "includes all existing permissions" do
        expect(permissions_hash.keys).to contain_exactly(*Permission.permissions_hash.keys)
      end

      it "returns all permissions as true" do
        expect(permissions_hash.values).to all(be true)
      end
    end

    context "with finance role" do
      let(:membership) { create(:membership, role: :finance) }

      it "includes all existing permissions" do
        expect(permissions_hash.keys).to contain_exactly(*Permission.permissions_hash.keys)
      end

      it "returns true for finance-specific permissions" do
        expect(permissions_hash).to include("analytics:view" => true)
      end

      it "returns false for non-finance permissions" do
        expect(permissions_hash).to include("coupons:attach" => false)
      end
    end

    context "with manager role" do
      let(:membership) { create(:membership, role: :manager) }

      it "includes all existing permissions" do
        expect(permissions_hash.keys).to contain_exactly(*Permission.permissions_hash.keys)
      end

      it "returns true for manager-specific permissions" do
        expect(permissions_hash).to include("coupons:attach" => true)
      end

      it "returns false for non-manager permissions" do
        expect(permissions_hash).to include("analytics:view" => false)
      end
    end
  end
end
