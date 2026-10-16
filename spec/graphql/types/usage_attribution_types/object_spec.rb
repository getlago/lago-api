# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::UsageAttributionTypes::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:organization).of_type("Organization") }
  it { is_expected.to have_field(:attribution_keys).of_type("[String!]!") }
  it { is_expected.to have_field(:code).of_type("String!") }
  it { is_expected.to have_field(:description).of_type("String") }
  it { is_expected.to have_field(:name).of_type("String") }
  it { is_expected.to have_field(:role).of_type("UsageAttributionTypeRoleEnum!") }
  it { is_expected.to have_field(:children).of_type("[UsageAttributionType!]!") }
  it { is_expected.to have_field(:parent).of_type("UsageAttributionType") }
  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }
end
