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
end
