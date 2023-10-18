# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::PaymentProviders::GocardlessInput do
  subject { described_class }

  it { is_expected.to accept_argument(:access_code).of_type('String') }
  it { is_expected.to accept_argument(:success_redirect_url).of_type('String') }
end
