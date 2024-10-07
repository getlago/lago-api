# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaign, type: :model do
  subject(:dunning_campaign) { create(:dunning_campaign) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:thresholds).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }

  it { is_expected.to validate_numericality_of(:days_between_attempts).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:max_attempts).is_greater_than(0) }

  it { is_expected.to validate_uniqueness_of(:code).scoped_to(:organization_id) }
end
