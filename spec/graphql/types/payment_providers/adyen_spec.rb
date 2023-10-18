# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PaymentProviders::Adyen do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:api_key).of_type('String!') }
  it { is_expected.to have_field(:hmac_key).of_type('String') }
  it { is_expected.to have_field(:live_prefix).of_type('String') }
  it { is_expected.to have_field(:merchant_account).of_type('String!') }
  it { is_expected.to have_field(:success_redirect_url).of_type('String') }
end
