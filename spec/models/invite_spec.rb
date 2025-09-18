# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invite do
  subject(:invite) { create(:invite) }

  it_behaves_like "paper_trail traceable"

  describe "#mark_as_revoked" do
    it "revokes the invite with a Time" do
      freeze_time do
        expect { invite.mark_as_revoked! }
          .to change { invite.reload.status }.from("pending").to("revoked")
          .and change(invite, :revoked_at).from(nil).to(Time.current)
      end
    end
  end

  describe "#mark_as_accepted" do
    it "accepts the invite with a Time" do
      freeze_time do
        expect { invite.mark_as_accepted! }
          .to change { invite.reload.status }.from("pending").to("accepted")
          .and change(invite, :accepted_at).from(nil).to(Time.current)
      end
    end
  end

  describe "Invite email" do
    let(:invite) { build(:invite) }

    it "is valid by default" do
      expect(invite).to be_valid
    end

    it "is invalid with wrong format" do
      invite.email = "wrong"
      expect(invite).not_to be_valid
    end

    it "is invalid if not present" do
      invite.email = nil
      expect(invite).not_to be_valid
    end
  end
end
