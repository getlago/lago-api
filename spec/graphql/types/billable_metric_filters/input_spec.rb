# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::BillableMetricFilters::Input do
  subject { described_class }

  it { is_expected.to accept_argument(:key).of_type("String!") }
  it { is_expected.to accept_argument(:values).of_type("[String!]!") }
end
