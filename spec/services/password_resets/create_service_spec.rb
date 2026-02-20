# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordResets::CreateService do
  subject(:create_service) { described_class }

  include_context "with mocked security logger"

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:membership) { create(:membership, organization:) }
    let(:user) { membership.user }
    let(:create_args) do
      {
        user:
      }
    end

    it "creates a password reset" do
      expect { create_service.call(**create_args) }
        .to change(PasswordReset, :count).by(1)
    end

    it "produces a security log" do
      create_service.call(**create_args)

      expect(security_logger).to have_received(:produce).with(
        organization: organization,
        log_type: "user",
        log_event: "user.password_reset_requested",
        user: user,
        resources: {email: user.email}
      )
    end

    context "with multiple active memberships" do
      let!(:other_organization) { create(:membership, user:).organization }

      it "produces a security log for each organization" do
        create_service.call(**create_args)

        expect(security_logger).to have_received(:produce).with(
          organization: organization,
          log_type: "user",
          log_event: "user.password_reset_requested",
          user: user,
          resources: {email: user.email}
        )

        expect(security_logger).to have_received(:produce).with(
          organization: other_organization,
          log_type: "user",
          log_event: "user.password_reset_requested",
          user: user,
          resources: {email: user.email}
        )
      end
    end

    context "without arguments" do
      it "raises an error" do
        result = create_service.call(user: nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("user_not_found")
      end

      it "does not produce a security log" do
        create_service.call(user: nil)

        expect(security_logger).not_to have_received(:produce)
      end
    end

    it "enqueues an SendEmailJob" do
      expect do
        create_service.call(**create_args)
      end.to have_enqueued_job(SendEmailJob)
    end
  end
end
