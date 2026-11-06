# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::UserActiveMembership do
  subject(:source) { described_class.new(user.id) }

  let(:user) { create(:user) }

  describe "#fetch" do
    it "answers per organization, in the order of the ids, counting only the user's active memberships" do
      member_of = create(:membership, user:).organization
      revoked = create(:membership, :revoked, user:).organization
      other_users = create(:membership).organization
      unrelated = create(:organization)

      result = source.fetch([member_of.id, revoked.id, other_users.id, unrelated.id])

      expect(result).to eq([true, false, false, false])
    end
  end
end
