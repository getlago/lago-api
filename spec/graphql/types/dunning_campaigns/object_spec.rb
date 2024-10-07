# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::DunningCampaigns::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }

  it { is_expected.to have_field(:applied_to_organization).of_type("Boolean!") }
  it { is_expected.to have_field(:code).of_type("String!") }
  it { is_expected.to have_field(:days_between_attempts).of_type("Int!") }
  it { is_expected.to have_field(:max_attempts).of_type("Int!") }
  it { is_expected.to have_field(:name).of_type("String!") }

  it { is_expected.to have_field(:description).of_type("String") }

  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }
end
