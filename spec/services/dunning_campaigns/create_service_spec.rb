# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:params) do
    {
      name: "Dunning Campaign",
      code: "dunning-campaign",
      days_between_attempts: 1,
      max_attempts: 3,
      description: "Dunning Campaign Description",
      applied_to_organization: true
    }
  end

  describe "#call" do
    it "creates a dunning campaign" do
      expect { create_service.call }.to change(DunningCampaign, :count).by(1)
    end

    it "returns dunning campaign in the result" do
      result = create_service.call
      expect(result.dunning_campaign).to be_a(DunningCampaign)
    end

    context "with validation error" do
      before { create(:dunning_campaign, organization: organization, code: "dunning-campaign") }

      it "returns an error" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(["value_already_exist"])
        end
      end
    end
  end
end
