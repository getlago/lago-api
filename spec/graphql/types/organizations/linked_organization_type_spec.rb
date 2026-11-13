# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Organizations::LinkedOrganizationType do
  subject { described_class }

  it do
    expect(subject.graphql_name).to eq("LinkedOrganization")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:slug).of_type("String!")
  end

  it "exposes nothing else, so it cannot reach sensitive or link fields" do
    expect(subject.fields.keys).to match_array(%w[id name slug])
  end
end
