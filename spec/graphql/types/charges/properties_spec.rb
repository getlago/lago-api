# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Charges::Properties do
  subject { described_class }

  it { is_expected.to have_field(:amount).of_type('String') }
  it { is_expected.to have_field(:grouped_by).of_type('[String!]') }

  it { is_expected.to have_field(:graduated_ranges).of_type('[GraduatedRange!]') }

  it { is_expected.to have_field(:graduated_percentage_ranges).of_type('[GraduatedPercentageRange!]') }

  it { is_expected.to have_field(:free_units).of_type('BigInt') }
  it { is_expected.to have_field(:package_size).of_type('BigInt') }

  it { is_expected.to have_field(:fixed_amount).of_type('String') }
  it { is_expected.to have_field(:free_units_per_events).of_type('BigInt') }
  it { is_expected.to have_field(:free_units_per_total_aggregation).of_type('String') }
  it { is_expected.to have_field(:per_transaction_max_amount).of_type('String') }
  it { is_expected.to have_field(:per_transaction_min_amount).of_type('String') }
  it { is_expected.to have_field(:rate).of_type('String') }

  it { is_expected.to have_field(:volume_ranges).of_type('[VolumeRange!]') }

  it { is_expected.to have_field(:custom_properties).of_type('JSON') }
end
