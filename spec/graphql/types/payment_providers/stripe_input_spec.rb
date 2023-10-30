# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PaymentProviders::StripeInput do
  subject { described_class }

  it { is_expected.to accept_argument(:create_customers).of_type('Boolean') }
  it { is_expected.to accept_argument(:secret_key).of_type('String') }
  it { is_expected.to accept_argument(:success_redirect_url).of_type('String') }
end
