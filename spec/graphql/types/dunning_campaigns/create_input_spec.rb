# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::DunningCampaigns::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:applied_to_organization).of_type("Boolean!")
    expect(subject).to accept_argument(:code).of_type("String!")
    expect(subject).to accept_argument(:days_between_attempts).of_type("Int!")
    expect(subject).to accept_argument(:max_attempts).of_type("Int!")
    expect(subject).to accept_argument(:name).of_type("String!")
    expect(subject).to accept_argument(:thresholds).of_type("[DunningCampaignThresholdInput!]!")

    expect(subject).to accept_argument(:description).of_type("String")
  end
end
