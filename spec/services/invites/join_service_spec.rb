# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::JoinService do
  subject(:join_service) { described_class.new(token:, user:, login_method:) }

  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:invite) { create(:invite, organization:, email: user.email, roles: %w[admin]) }
  let(:token) { invite.token }
  let(:login_method) { Organizations::AuthenticationMethods::EMAIL_PASSWORD }

  describe "#call" do
    it "creates a membership for the authenticated user" do
      result = join_service.call

      expect(result).to be_success
      expect(result.membership).to be_persisted
      expect(result.membership.user).to eq(user)
      expect(result.membership.organization).to eq(organization)
      expect(result.membership.roles.pluck(:code)).to eq(%w[admin])
    end

    it "sets the recipient of the invite" do
      expect { join_service.call }.to change { invite.reload.membership_id }.from(nil)
    end

    it "marks the invite as accepted" do
      freeze_time do
        expect { join_service.call }
          .to change { invite.reload.status }.from("pending").to("accepted")
          .and change(invite, :accepted_at).from(nil).to(Time.current)
      end
    end

    it "does not change the password of the user" do
      expect { join_service.call }.not_to change { user.reload.password_digest }
    end

    context "when the email of the invite has a different case" do
      let(:user) { create(:user, email: "invited@example.com") }
      let(:invite) { create(:invite, organization:, email: "Invited@example.com") }

      it "creates the membership" do
        result = join_service.call

        expect(result).to be_success
        expect(result.membership.user).to eq(user)
      end
    end

    context "when the invite targets another email" do
      let(:invite) { create(:invite, organization:, email: Faker::Internet.email) }

      it "returns an invite_email_mistmatch error" do
        result = join_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email]).to eq(["invite_email_mistmatch"])
      end

      it "does not create a membership" do
        expect { join_service.call }.not_to change(Membership, :count)
      end
    end

    context "when the invite does not exist" do
      let(:token) { "unknown" }

      it "returns a not found error" do
        result = join_service.call

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("invite_not_found")
      end
    end

    context "without user" do
      let(:user) { nil }
      let(:invite) { create(:invite, organization:, email: Faker::Internet.email) }

      it "returns a not found error" do
        result = join_service.call

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("user_not_found")
      end
    end

    context "when the invite is revoked" do
      let(:invite) { create(:invite, organization:, email: user.email, status: :revoked) }

      it "returns a not found error" do
        result = join_service.call

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("invite_not_found")
      end
    end

    context "when the invite is already accepted" do
      let(:invite) { create(:invite, organization:, email: user.email, status: :accepted) }

      it "returns a not found error" do
        result = join_service.call

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("invite_not_found")
      end
    end

    context "when the user is already an active member of the organization" do
      before { create(:membership, organization:, user:) }

      it "returns an email_already_used error" do
        result = join_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email]).to eq(["email_already_used"])
      end
    end

    context "when the user has been revoked from the organization" do
      before { create(:membership, :revoked, organization:, user:) }

      it "creates a new membership" do
        result = join_service.call

        expect(result).to be_success
        expect(result.membership).to be_persisted
        expect(result.membership).to be_active
      end
    end

    context "when the login method is not authorized by the organization" do
      before { organization.disable_email_password_authentication! }

      it "returns a login_method_not_authorized error" do
        result = join_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email_password]).to eq(["login_method_not_authorized"])
      end

      it "does not create a membership" do
        expect { join_service.call }.not_to change(Membership, :count)
      end
    end
  end
end
