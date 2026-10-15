# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordResets::CreateService do
  subject(:create_service) { described_class }

  include_context "with mocked security logger"

  describe "#call" do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:membership) { create(:membership, organization:) }
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

    it_behaves_like "produces a security log", "user.password_reset_requested" do
      before { create_service.call(**create_args) }
    end

    context "with multiple active memberships" do
      before { create(:membership, user:) }

      it_behaves_like "produces a security log", "user.password_reset_requested" do
        before { create_service.call(**create_args) }
      end
    end

    context "without user" do
      it "succeeds without creating a password reset or sending an email" do
        result = nil

        expect { result = create_service.call(user: nil) }
          .to not_change(PasswordReset, :count)
          .and not_have_enqueued_job(SendEmailJob)

        expect(result).to be_success
      end

      it_behaves_like "does not produce a security log" do
        before { create_service.call(user: nil) }
      end
    end

    it "enqueues an SendEmailJob" do
      expect do
        create_service.call(**create_args)
      end.to have_enqueued_job(SendEmailJob)
    end
  end
end
