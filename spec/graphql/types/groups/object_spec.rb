# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Groups::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:key).of_type("String") }
  it { is_expected.to have_field(:value).of_type("String!") }

  it { is_expected.to have_field(:deleted_at).of_type("ISO8601DateTime") }
end
