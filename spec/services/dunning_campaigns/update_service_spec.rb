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

  describe "#call", :aggregate_failures do
    subject(:result) { update_service.call }

    before do
      dunning_campaign
    end

    context "when lago freemium" do
      it 'returns an error' do
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
        it 'returns an error' do
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

        let(:dunning_campaign_threshold) do
          create(:dunning_campaign_threshold, dunning_campaign:)
        end

        let(:params) do
          {
            name: "Updated Dunning Campaign",
            code: "updated-dunning-campaign",
            days_between_attempts: Faker::Number.number(digits: 2),
            max_attempts: Faker::Number.number(digits: 2),
            description: "Updated Dunning Campaign Description",
            thresholds: thresholds_input
          }
        end

        let(:thresholds_input) do
          [
            {
              id: dunning_campaign_threshold.id,
              amount_cents: 999_99,
              currency: "GBP"
            },
            {
              amount_cents: 5_55,
              currency: "CHF"
            }
          ]
        end

        it "updates the dunning campaign" do
          expect(result).to be_success
          expect(result.dunning_campaign.name).to eq(params[:name])
          expect(result.dunning_campaign.code).to eq(params[:code])
          expect(result.dunning_campaign.days_between_attempts).to eq(params[:days_between_attempts])
          expect(result.dunning_campaign.max_attempts).to eq(params[:max_attempts])
          expect(result.dunning_campaign.description).to eq(params[:description])

          expect(result.dunning_campaign.thresholds.count).to eq(2)
          expect(result.dunning_campaign.thresholds.find(dunning_campaign_threshold.id))
            .to have_attributes({amount_cents: 999_99, currency: "GBP"})
          expect(result.dunning_campaign.thresholds.where.not(id: dunning_campaign_threshold.id).first)
            .to have_attributes({amount_cents: 5_55, currency: "CHF"})
        end

        context "when the input does not include a thresholds" do
          let(:dunning_campaign_threshold_to_be_deleted) do
            create(:dunning_campaign_threshold, dunning_campaign:, currency: "EUR")
          end

          before { dunning_campaign_threshold_to_be_deleted }

          it "deletes the thresholds not in the input" do
            expect(result).to be_success
            expect(result.dunning_campaign.thresholds.count).to eq(2)
            expect(result.dunning_campaign.thresholds.find_by(id: dunning_campaign_threshold_to_be_deleted.id)).to be_nil
            expect(dunning_campaign_threshold_to_be_deleted.reload).to be_discarded
          end
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
          let(:thresholds_input) { nil }

          it "returns a failure" do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq("dunning_campaign_not_found")
          end
        end
      end
    end
  end
end
