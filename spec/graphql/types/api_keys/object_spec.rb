# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::ApiKeys::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:value).of_type('String!') }
  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
end
