# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersService do
  before { create(:role, :admin) }

  describe ".call(:register)" do
    include_context "with mocked security logger"

    before { allow(UserDevices::RegisterService).to receive(:call!) }

    it "registers the user device" do
      result = described_class.call(:register, "email", "password", "organization_name")

      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user, skip_log: true)
    end

    it "calls SegmentIdentifyJob" do
      result = described_class.call(:register, "email", "password", "organization_name")

      expect(SegmentIdentifyJob).to have_been_enqueued.with(
        membership_id: "membership/#{result.membership.id}"
      )
    end

    it "calls SegmentTrackJob" do
      result = described_class.call(:register, "user@email.com", "password", "organization_name")

      expect(SegmentTrackJob).to have_been_enqueued.with(
        membership_id: "membership/#{result.membership.id}",
        event: "organization_registered",
        properties: {
          organization_name: result.organization.name,
          organization_id: result.organization.id,
          email: result.user.email
        }
      )
    end

    it_behaves_like "produces a security log", "user.signed_up" do
      before { described_class.call(:register, "email", "password", "organization_name") }
    end

    it "creates an organization, user and membership" do
      result = described_class.call(:register, "email", "password", "organization_name")

      expect(result).to be_a(BaseResult)
      expect(result.user).to be_present
      expect(result.membership).to be_present
      expect(result.token).to be_present

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::EMAIL_PASSWORD)

      expect(result.organization)
        .to be_present
        .and have_attributes(name: "organization_name", document_numbering: "per_organization")
    end

    context "when user already exists" do
      let(:user) { create(:user) }

      it "fails" do
        result = described_class.call(:register, user.email, "password", "organization_name")

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:email)
        expect(result.error.messages[:email]).to include("user_already_exists")
      end

      it_behaves_like "does not produce a security log" do
        before { described_class.call(:register, user.email, "password", "organization_name") }
      end

      context "when the email differs only by case" do
        subject(:registration_result) do
          described_class.call(:register, "jane@acme.com", "password", "organization_name")
        end

        let(:user) { create(:user, email: "Jane@acme.com") }

        before { user }

        it "fails without creating a duplicate user" do
          expect { registration_result }.not_to change(User, :count)
          expect(registration_result).not_to be_success
          expect(registration_result.error.messages[:email]).to include("user_already_exists")
        end
      end
    end

    context "when signup is disabled" do
      before do
        ENV["LAGO_DISABLE_SIGNUP"] = "true"
      end

      after do
        ENV["LAGO_DISABLE_SIGNUP"] = nil
      end

      it "returns a forbidden error" do
        result = described_class.call(:register, "email", "password", "organization_name")

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("signup_disabled")
      end

      it_behaves_like "does not produce a security log" do
        before { described_class.call(:register, "email", "password", "organization_name") }
      end
    end
  end

  describe ".call(:register_from_invite)" do
    subject(:registration_result) { described_class.call(:register_from_invite, invite, password, login_method:) }

    let(:email) { Faker::Internet.email }
    let(:password) { SecureRandom.hex(16) }
    let(:invite) { create(:invite, email:) }
    let(:login_method) { Organizations::AuthenticationMethods::EMAIL_PASSWORD }

    context "when is existing user" do
      let(:user) { create(:user, email:, password: "old_password") }
      let(:password) { "old_password" }

      before { user }

      it "reuse user and adds membership" do
        result = registration_result

        expect(result.user).to be_persisted
        expect(result.user.email).to eq email
        expect(result.membership).to be_persisted
        expect(result.organization).to eq invite.organization
        expect(result.token).to be_present
      end

      context "with an incorrect password" do
        let(:password) { "wrong_password" }

        before { invite }

        it "does not grant a membership or session" do
          expect { registration_result }.not_to change(Membership, :count)
          expect(registration_result).not_to be_success
          expect(registration_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
          expect(registration_result.token).to be_nil
          expect(user.reload.authenticate("old_password")).to eq(user)
        end

        context "without a password" do
          let(:password) { nil }

          it "returns a validation failure" do
            expect(registration_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
            expect(registration_result.token).to be_nil
          end
        end

        context "with a null byte in the password" do
          let(:password) { "old_password\u0000" }

          it "returns a validation failure" do
            expect(registration_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
            expect(registration_result.token).to be_nil
          end
        end

        context "with an identity verified by SSO" do
          let(:login_method) { Organizations::AuthenticationMethods::GOOGLE_OAUTH }

          it "reuses the account without checking or replacing its password" do
            expect { registration_result }.not_to change { user.reload.password_digest }
            expect(registration_result).to be_success
            expect(registration_result.user).to eq(user)
            expect(registration_result.token).to be_present
          end
        end
      end

      context "without active memberships" do
        before { create(:membership, user:, status: :revoked) }

        it "keeps the existing password" do
          expect { registration_result }.not_to change { user.reload.password_digest }
          expect(registration_result).to be_success
          expect(registration_result.user).to eq(user)
          expect(registration_result.token).to be_present
        end
      end

      context "when the invite email differs from the user email by case" do
        let(:invite) { create(:invite, email: email.upcase) }

        it "reuses the existing user" do
          result = registration_result

          expect(result.user).to eq user
          expect(User.where("lower(email) = ?", email.downcase).count).to eq(1)
        end
      end

      context "with active memberships" do
        before { create(:membership, user:, status: :active) }

        it "keeps the existing password" do
          expect { registration_result }.not_to change { user.reload.password_digest }
          expect(registration_result).to be_success
          expect(registration_result.user).to eq(user)
          expect(registration_result.token).to be_present
        end
      end

      context "when the user's organization requires SSO" do
        let(:sso_organization) { create(:organization, authentication_methods: %w[google_oauth]) }

        before do
          create(:membership, user:, organization: sso_organization)
          invite
        end

        it "does not grant a password session" do
          expect { registration_result }.not_to change(Membership, :count)
          expect(registration_result).not_to be_success
          expect(registration_result.error.messages[:email_password]).to eq(["login_method_not_authorized"])
          expect(registration_result.token).to be_nil
        end
      end
    end

    context "when is a new user" do
      it "creates user and membership" do
        result = registration_result

        expect(result).to be_a(BaseResult)
        expect(result.user).to be_persisted
        expect(result.user.email).to eq email
        expect(result.membership).to be_present
        expect(result.organization).to eq invite.organization
        expect(result.token).to be_present
      end
    end
  end

  describe ".call(:login)" do
    subject(:result) { described_class.call(:login, email, password) }

    before_all do
      create_default(:organization)
    end

    let_it_be(:membership) { create(:membership, :revoked) }
    let_it_be(:user) { membership.user }

    context "when user with given email exists" do
      let(:email) { user.email }

      context "when password is correct" do
        let(:password) { user.password }

        context "when user has active membership" do
          let_it_be(:active_membership, refind: true) { create(:membership, user:, organization: membership.organization) }

          before { allow(UserDevices::RegisterService).to receive(:call!) }

          it "registers the user device" do
            result

            expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user)
          end

          it "returns success result" do
            expect(result).to be_a(BaseResult)
            expect(result).to be_success
            expect(result.user).to eq user
            expect(result.token).to be_present
          end

          it "calls SegmentIdentifyJob with user's first active membership" do
            subject

            expect(SegmentIdentifyJob).to have_been_enqueued.with(
              membership_id: "membership/#{active_membership.id}"
            )
          end

          context "when login succeed" do
            it "saves the login method in token" do
              expect(result).to be_success

              decoded = Utils::AuthToken.decode(token: result.token)
              expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::EMAIL_PASSWORD)
            end
          end

          context "when login method is not allowed" do
            before { active_membership.organization.disable_email_password_authentication! }

            it "fails with login method not authorized" do
              expect(result).to be_failure
              expect(result.user).to eq user
              expect(result.token).to be nil
              expect(result.error.messages).to match(email_password: ["login_method_not_authorized"])
            end
          end
        end

        context "when user has no active membership" do
          it "fails with incorrect credentials error" do
            expect(result).to be_failure
            expect(result.user).to eq user
            expect(result.token).to be nil
            expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
          end

          it "does not call SegmentIdentifyJob" do
            subject

            expect(SegmentIdentifyJob).not_to have_been_enqueued
          end
        end
      end

      context "when password is incorrect" do
        let(:password) { "invalid-password" }

        context "when user has active membership" do
          before { create(:membership, user:, organization: membership.organization) }

          it "fails with incorrect credentials error" do
            expect(result).to be_failure
            expect(result.user).to be false
            expect(result.token).to be nil
            expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
          end

          it "does not call SegmentIdentifyJob" do
            subject

            expect(SegmentIdentifyJob).not_to have_been_enqueued
          end
        end

        context "when user has no active membership" do
          it "fails with incorrect credentials error" do
            expect(result).to be_failure
            expect(result.user).to be false
            expect(result.token).to be nil
            expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
          end

          it "does not call SegmentIdentifyJob" do
            subject

            expect(SegmentIdentifyJob).not_to have_been_enqueued
          end
        end
      end

      context "when email contains \u0000" do
        let(:email) { "email\u0000" }
        let(:password) { user.password }

        it "fails with invalid email or password error" do
          expect(result).to be_failure
          expect(result.user).to be nil
          expect(result.token).to be nil
          expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
        end
      end

      context "when password contains \u0000" do
        let(:email) { user.email }
        let(:password) { "password\u0000" }

        it "fails with invalid email or password error" do
          expect(result).to be_failure
          expect(result.user).to be nil
          expect(result.token).to be nil
          expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
        end
      end
    end

    context "when user with given does not email exist" do
      let(:email) { "non-existing-user@email.com" }
      let(:password) { "invalid-password" }

      it "fails with incorrect credentials error" do
        expect(result).to be_failure
        expect(result.user).to be nil
        expect(result.token).to be nil
        expect(result.error.messages).to match(base: ["incorrect_login_or_password"])
      end

      it "does not call SegmentIdentifyJob" do
        subject

        expect(SegmentIdentifyJob).not_to have_been_enqueued
      end
    end

    context "when the stored email casing differs from the login email" do
      let(:email) { "jane@acme.com" }
      let(:password) { "password" }
      let(:mixed_case_user) { create(:user, email: "Jane@acme.com", password:) }

      before do
        create(:membership, :active, user: mixed_case_user)
        allow(UserDevices::RegisterService).to receive(:call!)
      end

      it "logs in the existing user" do
        expect(result).to be_success
        expect(result.user).to eq(mixed_case_user)
      end
    end
  end
end
