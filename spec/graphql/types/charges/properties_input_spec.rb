# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Charges::PropertiesInput do
  subject { described_class }

  it { is_expected.to accept_argument(:amount).of_type("String") }
  it { is_expected.to accept_argument(:grouped_by).of_type("[String!]") }

  it { is_expected.to accept_argument(:graduated_ranges).of_type("[GraduatedRangeInput!]") }

  it { is_expected.to accept_argument(:graduated_percentage_ranges).of_type("[GraduatedPercentageRangeInput!]") }

  it { is_expected.to accept_argument(:free_units).of_type("BigInt") }
  it { is_expected.to accept_argument(:package_size).of_type("BigInt") }

  it { is_expected.to accept_argument(:fixed_amount).of_type("String") }
  it { is_expected.to accept_argument(:free_units_per_events).of_type("BigInt") }
  it { is_expected.to accept_argument(:free_units_per_total_aggregation).of_type("String") }
  it { is_expected.to accept_argument(:per_transaction_max_amount).of_type("String") }
  it { is_expected.to accept_argument(:per_transaction_min_amount).of_type("String") }
  it { is_expected.to accept_argument(:rate).of_type("String") }

  it { is_expected.to accept_argument(:volume_ranges).of_type("[VolumeRangeInput!]") }
end
