# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaignThreshold, type: :model do
  subject(:dunning_campaign_threshold) { create(:dunning_campaign_threshold) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:dunning_campaign) }

  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_inclusion_of(:currency).in_array(described_class.currency_list) }
  it { is_expected.to validate_uniqueness_of(:currency).scoped_to(:dunning_campaign_id) }

  describe "currency validation" do
    let(:currency) { "EUR" }
    let(:dunning_campaign) { create(:dunning_campaign) }

    it "validates uniqueness of currency scoped to dunning_campaign_id excluding deleted records" do
      create(:dunning_campaign_threshold, currency:, dunning_campaign:)
      new_record = build(:dunning_campaign_threshold, currency:, dunning_campaign:)

      expect(new_record).not_to be_valid
      expect(new_record.errors[:currency]).to include("value_already_exist")

      # Records with deleted_at set should not conflict
      deleted_record = create(:dunning_campaign_threshold, :deleted, currency:, dunning_campaign:)
      expect(deleted_record).to be_valid
    end
  end

  describe "default scope" do
    let(:deleted_dunning_campaign_threshold) do
      create(:dunning_campaign_threshold, :deleted)
    end

    before { deleted_dunning_campaign_threshold }

    it "only returns non-deleted dunning_campaign_threshold objects" do
      expect(described_class.all).to eq([])
      expect(described_class.with_discarded).to eq([deleted_dunning_campaign_threshold])
    end
  end
end
