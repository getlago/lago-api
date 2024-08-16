# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Subscriptions::UsageThresholdOverridesInput do
  subject { described_class }

  it { is_expected.to accept_argument(:amount_cents).of_type('BigInt!') }
  it { is_expected.to accept_argument(:recurring).of_type('Boolean') }
  it { is_expected.to accept_argument(:threshold_display_name).of_type('String') }
end
