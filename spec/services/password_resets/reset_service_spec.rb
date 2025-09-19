# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordResets::ResetService do
  subject(:reset_service) { described_class }

  describe "#call" do
    let(:user) { create(:user, password: "HelloLago!1") }
    let(:membership) { create(:membership, user:) }
    let(:password_reset) { create(:password_reset, user: membership.user) }
    let(:reset_args) do
      {
        token: password_reset.token,
        new_password: "HelloLago!2"
      }
    end

    it "changes the user password" do
      reset_service.call(**reset_args)

      expect(user.saved_changes["password_digest"].class).to eq(Array)
      expect(user.reload&.authenticate(reset_args[:new_password])).to be_truthy
    end

    it "logs in the user" do
      allow(SegmentIdentifyJob).to receive(:perform_later)

      result = reset_service.call(**reset_args)

      data = result["user"]

      expect(data).to be_present
      expect(SegmentIdentifyJob).to have_received(:perform_later).with(
        membership_id: "membership/#{membership.id}"
      )
    end

    context "without expected argument" do
      it "raises an error if token is not present" do
        result = reset_service.call(new_password: reset_args[:new_password], token: nil)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:token]).to eq(["missing_token"])
      end

      it "raises an error if new_password is not present" do
        result = reset_service.call(new_password: nil, token: password_reset.token)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:new_password]).to eq(["missing_password"])
      end
    end

    context "when demand is expired" do
      let(:expired_password_reset) do
        create(:password_reset, user: membership.user, expire_at: Time.current - 1.minute)
      end

      it "raises an error" do
        result = reset_service.call(new_password: reset_args[:new_password], token: expired_password_reset.token)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("password_reset_not_found")
      end
    end
  end
end
