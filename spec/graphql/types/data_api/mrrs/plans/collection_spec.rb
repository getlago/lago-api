# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::DataApi::Mrrs::Plans::Collection do
  subject { described_class }

  it do
    expect(subject.graphql_name).to eq("DataApiMrrsPlans")
    expect(subject).to have_field(:mrrs_plans).of_type("[DataApiMrrPlan!]!")
    expect(subject).to have_field(:meta).of_type("DataApiMetadata!")
  end
end
