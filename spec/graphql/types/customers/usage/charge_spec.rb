# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Customers::Usage::Charge do
  subject { described_class }

  it { is_expected.to have_field(:amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:events_count).of_type('Int!') }
  it { is_expected.to have_field(:units).of_type('Float!') }
  it { is_expected.to have_field(:billable_metric).of_type('BillableMetric!') }
  it { is_expected.to have_field(:charge).of_type('Charge!') }
  it { is_expected.to have_field(:grouped_by).of_type('[String!]') }
  it { is_expected.to have_field(:groups).of_type('[GroupUsage!]') }
end
