# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::MembershipType do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:organization).of_type('Organization!') }
  it { is_expected.to have_field(:permissions).of_type('Permissions!') }
  it { is_expected.to have_field(:revoked_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:role).of_type('String') }
  it { is_expected.to have_field(:status).of_type('MembershipStatus!') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:user).of_type('User!') }
end
