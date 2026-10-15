# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::CreateFromInviteService do
  subject(:create_service) { described_class.new(invite:, user:) }

  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:invite) { create(:invite, organization:, email: user.email, roles: %w[admin]) }

  describe "#call" do
    it "creates a membership with the roles of the invite" do
      result = create_service.call

      expect(result).to be_success
      expect(result.membership).to be_persisted
      expect(result.membership.user).to eq(user)
      expect(result.membership.organization).to eq(organization)
      expect(result.membership.roles.pluck(:code)).to eq(%w[admin])
    end

    context "when the user is already an active member" do
      before { create(:membership, organization:, user:) }

      it "raises a record invalid error" do
        expect { create_service.call }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "when a role of the invite does not exist in the organization" do
      # The invite factory creates the missing roles, so it has to exist before they are destroyed.
      before do
        invite
        Role.with_organization(organization.id).with_code("admin").destroy_all
      end

      it "raises a record not found error" do
        expect { create_service.call }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
