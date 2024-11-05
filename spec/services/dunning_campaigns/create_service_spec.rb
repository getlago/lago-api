# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::CreateService, type: :service, aggregate_failures: true do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:organization) { create :organization }
  let(:params) do
    {
      name: "Dunning Campaign",
      code: "dunning-campaign",
      days_between_attempts: 1,
      max_attempts: 3,
      description: "Dunning Campaign Description",
      applied_to_organization:,
      thresholds:
    }
  end

  let(:applied_to_organization) { false }

  let(:thresholds) do
    [
      {amount_cents: 10000, currency: "USD"},
      {amount_cents: 20000, currency: "EUR"}
    ]
  end

  describe "#call" do
    context "when lago freemium" do
      it "returns an error" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end

      it "does not update the dunning campaign" do
        expect { create_service.call }.not_to change(DunningCampaign, :count)
      end
    end

    context "when lago premium" do
      around { |test| lago_premium!(&test) }

      context "when no auto_dunning premium integration" do
        it "returns an error" do
          result = create_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end

      context "when auto_dunning premium integration" do
        let(:organization) do
          create(:organization, premium_integrations: ["auto_dunning"])
        end

        it "creates a dunning campaign" do
          expect { create_service.call }.to change(DunningCampaign, :count).by(1)
            .and change(DunningCampaignThreshold, :count).by(2)
        end

        it "returns dunning campaign in the result" do
          result = create_service.call
          expect(result.dunning_campaign).to be_a(DunningCampaign)
          expect(result.dunning_campaign.thresholds.first).to be_a(DunningCampaignThreshold)
        end

        context "with a previous dunning campaign set as applied_to_organization" do
          let(:dunning_campaign_2) do
            create(:dunning_campaign, organization:, applied_to_organization: true)
          end

          before { dunning_campaign_2 }

          it "does not change previous dunning campaign applied_to_organization" do
            expect { create_service.call }
              .not_to change(dunning_campaign_2.reload, :applied_to_organization)
          end
        end

        context "with applied_to_organization true" do
          let(:applied_to_organization) { true }

          it "updates the dunning campaign" do
            result = create_service.call

            expect(result).to be_success
            expect(result.dunning_campaign.applied_to_organization).to eq(true)
          end

          context "with a previous dunning campaign set as applied_to_organization" do
            let(:dunning_campaign_2) do
              create(:dunning_campaign, organization:, applied_to_organization: true)
            end

            before { dunning_campaign_2 }

            it "removes applied_to_organization from previous dunning campaign" do
              expect { create_service.call }
                .to change { dunning_campaign_2.reload.applied_to_organization }
                .from(true)
                .to(false)
            end
          end
        end

        context "with validation error" do
          before do
            create(:dunning_campaign, organization:, code: "dunning-campaign")
          end

          it "returns an error" do
            result = create_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:code]).to eq(["value_already_exist"])
          end
        end

        context "without thresholds" do
          let(:thresholds) { [] }

          it "returns an error" do
            result = create_service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:thresholds]).to eq(["can't be blank"])
            end
          end
        end
      end
    end
  end
end
