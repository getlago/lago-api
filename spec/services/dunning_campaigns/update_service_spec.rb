# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::UpdateService, type: :service do
  subject(:update_service) { described_class.new(organization:, dunning_campaign:, params:) }

  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:dunning_campaign) do
    create(:dunning_campaign, organization:, applied_to_organization: true)
  end

  let(:params) { {applied_to_organization: false} }

  describe "#call" do
    subject(:result) { update_service.call }

    before do
      dunning_campaign
    end

    context "when lago freemium" do
      it 'returns an error', :aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end

      it "does not update the dunning campaign" do
        expect { result }.not_to change(dunning_campaign, :applied_to_organization)
      end
    end

    context "when lago premium" do
      around { |test| lago_premium!(&test) }

      context "when no auto_dunning premium integration" do
        it 'returns an error', :aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end

        it "does not update the dunning campaign" do
          expect { result }.not_to change(dunning_campaign, :applied_to_organization)
        end
      end

      context "when auto_dunning premium integration" do
        let(:organization) do
          create(:organization, premium_integrations: ["auto_dunning"])
        end

        context "with applied_to_organization false" do
          let(:params) { {applied_to_organization: false} }

          it "updates the dunning campaign" do
            expect(result).to be_success
            expect(result.dunning_campaign.applied_to_organization).to eq(false)
          end
        end

        context "with applied_to_organization true" do
          let(:params) { {applied_to_organization: true} }

          let(:dunning_campaign) do
            create(:dunning_campaign, organization:, applied_to_organization: false)
          end

          it "updates the dunning campaign" do
            expect(result).to be_success
            expect(result.dunning_campaign.applied_to_organization).to eq(true)
          end

          context "with a previous dunning campaign set as applied_to_organization" do
            let(:dunning_campaign_2) do
              create(:dunning_campaign, organization:, applied_to_organization: true)
            end

            before do
              dunning_campaign_2
            end

            it "removes applied_to_organization from previous dunning campaign" do
              expect { result }
                .to change { dunning_campaign_2.reload.applied_to_organization }
                .from(true)
                .to(false)
            end
          end

          it "stops and resets counters on customers" do
            customer = create(:customer, organization:, last_dunning_campaign_attempt: 1, last_dunning_campaign_attempt_at: Time.current)

            expect { result }.to change { customer.reload.last_dunning_campaign_attempt }.from(1).to(0)
              .and change { customer.last_dunning_campaign_attempt_at }.from(a_value).to(nil)
          end
        end

        context "with no dunning campaign record" do
          let(:dunning_campaign) { nil }

          it "returns a failure", :aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq("dunning_campaign_not_found")
          end
        end
      end
    end
  end
end
