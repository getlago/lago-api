# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::BillableMetrics::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:organization).of_type('Organization') }
  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:name).of_type('String!') }
  it { is_expected.to have_field(:description).of_type('String') }
  it { is_expected.to have_field(:aggregation_type).of_type('AggregationTypeEnum!') }
  it { is_expected.to have_field(:field_name).of_type('String') }
  it { is_expected.to have_field(:weighted_interval).of_type('WeightedIntervalEnum') }
  it { is_expected.to have_field(:filters).of_type('[BillableMetricFilter!]') }
  it { is_expected.to have_field(:active_subscriptions_count).of_type('Int!') }
  it { is_expected.to have_field(:draft_invoices_count).of_type('Int!') }
  it { is_expected.to have_field(:plans_count).of_type('Int!') }
  it { is_expected.to have_field(:recurring).of_type('Boolean!') }
  it { is_expected.to have_field(:subscriptions_count).of_type('Int!') }
  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:deleted_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:integration_mappings).of_type('[NetsuiteMapping!]') }
end
