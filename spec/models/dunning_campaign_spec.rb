# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaign, type: :model do
  subject(:dunning_campaign) { create(:dunning_campaign) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:thresholds).dependent(:destroy) }
  it { is_expected.to have_many(:customers).dependent(:nullify) }

  it { is_expected.to validate_presence_of(:name) }

  it { is_expected.to validate_numericality_of(:days_between_attempts).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:max_attempts).is_greater_than(0) }

  it { is_expected.to validate_uniqueness_of(:code).scoped_to(:organization_id) }

  describe "code validation" do
    let(:code) { "123456" }
    let(:organization) { create(:organization) }

    it "validates uniqueness of code scoped to organization_id excluding deleted records" do
      create(:dunning_campaign, code:, organization:)
      new_record = build(:dunning_campaign, code:, organization:)

      expect(new_record).not_to be_valid
      expect(new_record.errors[:code]).to include("value_already_exist")

      # Records with deleted_at set should not conflict
      deleted_record = create(:dunning_campaign, :deleted, code:, organization:)
      expect(deleted_record).to be_valid
    end
  end

  describe "default scope" do
    let(:deleted_dunning_campaign) { create(:dunning_campaign, :deleted) }

    before { deleted_dunning_campaign }

    it "only returns non-deleted dunning_campaign objects" do
      expect(described_class.all).to eq([])
      expect(described_class.with_discarded).to eq([deleted_dunning_campaign])
    end
  end

  describe "#reset_customers_last_attempt" do
    let(:last_dunning_campaign_attempt_at) { Time.current }
    let(:organization) { dunning_campaign.organization }

    it "resets last attempt on customers with the campaign applied explicitly" do
      customer = create(
        :customer,
        organization:,
        applied_dunning_campaign: dunning_campaign,
        last_dunning_campaign_attempt: 1,
        last_dunning_campaign_attempt_at:
      )

      expect { dunning_campaign.reset_customers_last_attempt }
        .to change { customer.reload.last_dunning_campaign_attempt }.from(1).to(0)
        .and change { customer.last_dunning_campaign_attempt_at }.from(last_dunning_campaign_attempt_at).to(nil)
    end

    context "when applied to organization" do
      subject(:dunning_campaign) { create(:dunning_campaign, applied_to_organization: true) }

      it "resets last attempt on customers falling back to the organization campaign" do
        customer = create(
          :customer,
          organization:,
          last_dunning_campaign_attempt: 2,
          last_dunning_campaign_attempt_at:
        )

        expect { dunning_campaign.reset_customers_last_attempt }
          .to change { customer.reload.last_dunning_campaign_attempt }.from(2).to(0)
          .and change { customer.last_dunning_campaign_attempt_at }.from(last_dunning_campaign_attempt_at).to(nil)
      end
    end
  end
end
