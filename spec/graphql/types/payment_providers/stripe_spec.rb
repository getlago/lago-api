# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PaymentProviders::Stripe do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:name).of_type('String!') }

  it { is_expected.to have_field(:secret_key).of_type('String').with_permission('organization:integrations:view') }
  it { is_expected.to have_field(:success_redirect_url).of_type('String').with_permission('organization:integrations:view') }
end
