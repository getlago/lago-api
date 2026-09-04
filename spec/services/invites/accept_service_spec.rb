# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::AcceptService do
  subject(:accept_service) { described_class.new }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invite) { create(:invite, organization:, email: Faker::Internet.email) }
  let(:accept_args) do
    {
      token: invite.token,
      password: "ILoveLago!",
      login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD
    }
  end

  describe "#call" do
    before { allow(UserDevices::RegisterService).to receive(:call!) }

    it "registers the user device" do
      result = accept_service.call(**accept_args)

      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user, skip_log: true)
    end

    it "sets the recipient of the invite" do
      expect { accept_service.call(**accept_args) }
        .to change { invite.reload.membership_id }.from(nil)
    end

    it "marks the invite as accepted" do
      freeze_time do
        expect { accept_service.call(**accept_args) }
          .to change { invite.reload.status }.from("pending").to("accepted")
          .and change(invite, :accepted_at).from(nil).to(Time.current)
      end
    end

    it "sets user, membership and organization" do
      result = accept_service.call(**accept_args)

      expect(result.user).to be_present
      expect(result.membership).to be_present
      expect(result.organization).to be_present
      expect(result.token).to be_present
    end

    context "when the invited email belongs to an existing user" do
      let!(:user) { create(:user, email: invite.email, password: "ILoveLago") }

      context "with an incorrect password" do
        it "returns an incorrect_login_or_password error" do
          result = accept_service.call(**accept_args)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:base]).to eq(["incorrect_login_or_password"])
        end

        it "does not create a membership nor accept the invite" do
          expect { accept_service.call(**accept_args) }.not_to change(Membership, :count)
          expect(invite.reload.status).to eq("pending")
        end

        it "does not change the password of the existing user" do
          expect { accept_service.call(**accept_args) }.not_to change { user.reload.password_digest }
        end

        context "when the user is an active member of another organization" do
          before { create(:membership, user:) }

          it "does not grant access to the organizations of the user" do
            expect { accept_service.call(**accept_args) }.not_to change { user.reload.memberships.count }
          end
        end
      end

      context "with the password of the existing user" do
        let(:accept_args) do
          {
            token: invite.token,
            password: "ILoveLago",
            login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD
          }
        end

        it "adds the membership to the existing user" do
          result = accept_service.call(**accept_args)

          expect(result).to be_success
          expect(result.user).to eq(user)
          expect(result.membership).to be_persisted
          expect(result.organization).to eq(organization)
          expect(result.token).to be_present
        end

        it "marks the invite as accepted" do
          expect { accept_service.call(**accept_args) }
            .to change { invite.reload.status }.from("pending").to("accepted")
        end

        it "keeps the existing password" do
          expect { accept_service.call(**accept_args) }.not_to change { user.reload.password_digest }
        end

        it "does not create another user" do
          expect { accept_service.call(**accept_args) }.not_to change(User, :count)
        end

        # A user whose memberships were all revoked cannot log in anymore: accepting an invitation
        # is the only way to restore their access.
        context "when all the memberships of the user are revoked" do
          before { create(:membership, :revoked, organization:, user:) }

          it "adds the membership to the existing user" do
            result = accept_service.call(**accept_args)

            expect(result).to be_success
            expect(result.user).to eq(user)
            expect(result.membership).to be_active
          end
        end

        # The authentication methods of the inviting organization are controlled by whoever created
        # the invitation: they must not let a password session be opened for a user whose own
        # organizations mandate SSO.
        context "when the organizations of the user do not allow the login method" do
          let(:user_organization) { create(:organization) }

          before do
            create(:membership, organization: user_organization, user:)
            user_organization.disable_email_password_authentication!
          end

          it "returns a login_method_not_authorized error" do
            result = accept_service.call(**accept_args)

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:email_password]).to eq(["login_method_not_authorized"])
          end

          it "does not create a membership nor accept the invite" do
            expect { accept_service.call(**accept_args) }.not_to change(Membership, :count)
            expect(invite.reload.status).to eq("pending")
          end

          it "does not issue a session" do
            expect(accept_service.call(**accept_args).token).to be_nil
          end

          context "when another organization of the user allows the login method" do
            before { create(:membership, user:) }

            it "adds the membership to the existing user" do
              result = accept_service.call(**accept_args)

              expect(result).to be_success
              expect(result.membership).to be_persisted
            end
          end

          context "when the memberships of the user are revoked" do
            before { user.memberships.each(&:mark_as_revoked!) }

            it "adds the membership to the existing user" do
              result = accept_service.call(**accept_args)

              expect(result).to be_success
              expect(result.membership).to be_active
            end
          end
        end

        context "when the user is already an active member of the organization" do
          before { create(:membership, organization:, user:) }

          it "returns an email_already_used error" do
            result = accept_service.call(**accept_args)

            expect(result).not_to be_success
            expect(result.error.messages[:email]).to eq(["email_already_used"])
          end
        end

        context "when the email of the invite has a different case" do
          let(:invite) { create(:invite, organization:, email: "Victim@example.com") }
          let!(:user) { create(:user, email: "victim@example.com", password: "ILoveLago") }

          # The organization of the invite comes with its own owner: it must exist before the
          # examples count the users.
          before { invite }

          it "adds the membership to the existing user" do
            result = accept_service.call(**accept_args)

            expect(result).to be_success
            expect(result.user).to eq(user)
          end

          it "does not create another user" do
            expect { accept_service.call(**accept_args) }.not_to change(User, :count)
          end
        end
      end

      context "when the login method verifies the identity" do
        let(:accept_args) do
          {
            token: invite.token,
            password: SecureRandom.hex,
            login_method: Organizations::AuthenticationMethods::GOOGLE_OAUTH
          }
        end

        it "adds the membership to the existing user" do
          result = accept_service.call(**accept_args)

          expect(result).to be_success
          expect(result.user).to eq(user)
          expect(result.membership).to be_persisted
          expect(result.token).to be_present
        end

        it "keeps the existing password" do
          expect { accept_service.call(**accept_args) }.not_to change { user.reload.password_digest }
        end
      end
    end

    context "when invite is already accepted" do
      let(:accepted_invite) { create(:invite, organization:, status: :accepted) }

      it "returns invite_not_found error" do
        result = accept_service.call(
          password: accept_args[:password],
          token: accepted_invite[:token],
          login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD
        )

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("invite_not_found")
      end
    end

    context "when invite is revoked" do
      let(:revoked_invite) { create(:invite, organization:, status: :revoked) }

      it "returns invite_not_found error" do
        result = accept_service.call(
          password: accept_args[:password],
          token: revoked_invite[:token],
          login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD
        )

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("invite_not_found")
      end
    end

    context "without password" do
      it "returns an error" do
        result = accept_service.call(password: nil, **accept_args.slice(:token, :login_method))

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:password]).to eq(["value_is_mandatory"])
      end

      context "without token" do
        it "returns invite_not_found error" do
          result = accept_service.call(password: accept_args[:password], token: nil)

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("invite_not_found")
        end
      end
    end

    context "with invalid login_method" do
      before do
        organization.disable_email_password_authentication!
      end

      it "returns an error" do
        result = accept_service.call(**accept_args)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email_password]).to eq(["login_method_not_authorized"])
      end
    end
  end
end
