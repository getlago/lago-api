# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaignThreshold, type: :model do
  subject(:dunning_campaign_threshold) { create(:dunning_campaign_threshold) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:dunning_campaign) }

  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_inclusion_of(:currency).in_array(described_class.currency_list) }
  it { is_expected.to validate_uniqueness_of(:currency).scoped_to(:dunning_campaign_id) }
end
