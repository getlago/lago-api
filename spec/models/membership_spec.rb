# frozen_string_literal: true

require "rails_helper"

RSpec.describe Membership do
  subject(:membership) { create(:membership) }

  it { is_expected.to have_many(:data_exports) }

  it_behaves_like "paper_trail traceable"

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
