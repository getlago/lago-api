# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::DunningCampaigns::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID!') }

  it { is_expected.to accept_argument(:applied_to_organization).of_type('Boolean!') }
end
