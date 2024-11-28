# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::ApiKeys::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID!') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:permissions).of_type('JSON') }
end
