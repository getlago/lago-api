# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Subscriptions::LifetimeUsageObject do
  subject { described_class }

  it { is_expected.to have_field(:total_usage_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:total_usage_from_datetime).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:total_usage_to_datetime).of_type('ISO8601DateTime!') }

  it { is_expected.to have_field(:last_threshold_amount_cents).of_type('BigInt') }
  it { is_expected.to have_field(:next_threshold_amount_cents).of_type('BigInt') }
  it { is_expected.to have_field(:next_threshold_ratio).of_type('Float') }
end
