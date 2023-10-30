# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PaymentProviders::AdyenInput do
  subject { described_class }

  it { is_expected.to accept_argument(:api_key).of_type('String!') }
  it { is_expected.to accept_argument(:hmac_key).of_type('String') }
  it { is_expected.to accept_argument(:live_prefix).of_type('String') }
  it { is_expected.to accept_argument(:merchant_account).of_type('String!') }
  it { is_expected.to accept_argument(:success_redirect_url).of_type('String') }
end
