# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::BillableMetricFilters::Input do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:key).of_type("String!")
    expect(subject).to accept_argument(:values).of_type("[String!]!")
  end
end
