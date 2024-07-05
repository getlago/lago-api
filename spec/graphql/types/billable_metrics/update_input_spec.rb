# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::BillableMetrics::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('String!') }
  it { is_expected.to accept_argument(:aggregation_type).of_type('AggregationTypeEnum!') }
  it { is_expected.to accept_argument(:code).of_type('String!') }
  it { is_expected.to accept_argument(:description).of_type('String!') }
  it { is_expected.to accept_argument(:field_name).of_type('String') }
  it { is_expected.to accept_argument(:name).of_type('String!') }
  it { is_expected.to accept_argument(:recurring).of_type('Boolean') }
  it { is_expected.to accept_argument(:weighted_interval).of_type('WeightedIntervalEnum') }
  it { is_expected.to accept_argument(:filters).of_type('[BillableMetricFiltersInput!]') }
end
