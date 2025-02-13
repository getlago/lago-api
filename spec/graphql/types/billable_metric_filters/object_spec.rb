# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::BillableMetricFilters::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:key).of_type("String!")
    expect(subject).to have_field(:values).of_type("[String!]!")
  end
end
