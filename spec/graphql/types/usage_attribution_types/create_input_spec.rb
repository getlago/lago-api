# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::UsageAttributionTypes::CreateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:attribution_keys).of_type("[String!]!") }
  it { is_expected.to accept_argument(:code).of_type("String!") }
  it { is_expected.to accept_argument(:description).of_type("String") }
  it { is_expected.to accept_argument(:name).of_type("String") }
  it { is_expected.to accept_argument(:parent_id).of_type("ID") }
  it { is_expected.to accept_argument(:role).of_type("UsageAttributionTypeRoleEnum!") }
end
