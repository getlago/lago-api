# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::CreateService do
  subject(:create_service) { described_class.new(create_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe "#call" do
    let(:create_args) do
      {
        email: Faker::Internet.email,
        current_organization: organization,
        role: "admin"
      }
    end

    it "creates an invite" do
      expect { create_service.call }
        .to change(Invite, :count).by(1)
    end

    context "with validation error" do
      let(:create_args) do
        {
          current_organization: organization,
          role: "admin"
        }
      end

      it "returns an error" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:email]).to eq(["invalid_email_format"])
        end
      end
    end

    context "with missing role" do
      let(:create_args) do
        {
          email: Faker::Internet.email,
          current_organization: organization
        }
      end

      it "returns an error" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:role]).to eq(["invalid_role"])
        end
      end
    end

    context "with already existing invite" do
      it "returns an error" do
        create(:invite, organization: create_args[:current_organization], email: create_args[:email])
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to eq([:invite])
        end
      end
    end

    context "with already existing member" do
      let(:user) { create(:user, email: create_args[:email]) }

      it "returns an error" do
        create(:membership, organization:, user:)

        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to eq([:email])
        end
      end
    end
  end
end
