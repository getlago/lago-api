# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::ApiKeys::RotateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID!') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:expires_at).of_type('ISO8601DateTime') }
end
