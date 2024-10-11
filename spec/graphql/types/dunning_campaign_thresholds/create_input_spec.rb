# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::DunningCampaignThresholds::CreateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:amount_cents).of_type("BigInt!") }
  it { is_expected.to accept_argument(:currency).of_type("CurrencyEnum!") }
end
