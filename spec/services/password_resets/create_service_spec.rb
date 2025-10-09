# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordResets::CreateService do
  subject(:create_service) { described_class }

  describe "#call" do
    let(:user) { create(:user) }
    let(:create_args) do
      {
        user:
      }
    end

    it "creates a password reset" do
      expect { create_service.call(**create_args) }
        .to change(PasswordReset, :count).by(1)
    end

    context "without arguments" do
      it "raises an error" do
        result = create_service.call(user: nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("user_not_found")
      end
    end

    it "enqueues an SendEmailJob" do
      expect do
        create_service.call(**create_args)
      end.to have_enqueued_job(SendEmailJob)
    end
  end
end
