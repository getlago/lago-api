# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Organizations::OrganizationType do
  subject { described_class }

  it { is_expected.to be < ::Types::Organizations::BaseOrganizationType }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:logo_url).of_type('String') }
  it { is_expected.to have_field(:name).of_type('String!') }
  it { is_expected.to have_field(:timezone).of_type('TimezoneEnum') }
  it { is_expected.to have_field(:default_currency).of_type('CurrencyEnum!') }
end
