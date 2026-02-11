# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::CreateService do
  subject(:create_service) { described_class.new(create_args) }

  include_context "with mocked security logger"

  before { create(:role, :admin) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe "#call" do
    let(:create_args) do
      {
        email: Faker::Internet.email,
        current_organization: organization,
        roles: %w[admin]
      }
    end

    it "creates an invite" do
      expect { create_service.call }
        .to change(Invite, :count).by(1)
    end

    it "produces a security log" do
      create_service.call

      expect(security_logger).to have_received(:produce).with(
        organization: organization,
        log_type: "user",
        log_event: "user.invited",
        resources: {invitee_email: create_args[:email]}
      )
    end

    context "with validation error" do
      let(:create_args) do
        {
          current_organization: organization,
          roles: %w[admin]
        }
      end

      it "returns an error" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:email]).to eq(%w[invalid_email_format])
      end

      it "does not produce a security log" do
        create_service.call

        expect(security_logger).not_to have_received(:produce)
      end
    end

    context "with missing roles" do
      let(:create_args) do
        {
          email: Faker::Internet.email,
          current_organization: organization
        }
      end

      it "returns an error" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end

      it "does not produce a security log" do
        create_service.call

        expect(security_logger).not_to have_received(:produce)
      end
    end

    context "with invalid roles" do
      let(:create_args) do
        {
          email: Faker::Internet.email,
          current_organization: organization,
          roles: %w[nonexistent_role]
        }
      end

      it "returns an error" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:roles]).to eq(%w[invalid_role])
      end

      it "does not produce a security log" do
        create_service.call

        expect(security_logger).not_to have_received(:produce)
      end
    end

    context "with already existing invite" do
      it "returns an error" do
        create(:invite, organization: create_args[:current_organization], email: create_args[:email])
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to eq([:invite])
      end

      it "does not produce a security log" do
        create(:invite, organization: create_args[:current_organization], email: create_args[:email])
        create_service.call

        expect(security_logger).not_to have_received(:produce)
      end
    end

    context "with already existing member" do
      let(:user) { create(:user, email: create_args[:email]) }

      it "returns an error" do
        create(:membership, organization:, user:)

        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to eq([:email])
      end

      it "does not produce a security log" do
        create(:membership, organization:, user:)
        create_service.call

        expect(security_logger).not_to have_received(:produce)
      end
    end
  end
end
