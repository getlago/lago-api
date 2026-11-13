# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Admin::OrganizationType do
  subject { described_class }

  it do
    expect(subject.graphql_name).to eq("AdminOrganization")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:email).of_type("String")
    expect(subject).to have_field(:environment).of_type("OrganizationEnvironmentEnum!")
    expect(subject).to have_field(:feature_flags).of_type("[String!]!")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:premium_integrations).of_type("[String!]!")
    expect(subject).to have_field(:production_organization).of_type("LinkedOrganization")
    expect(subject).to have_field(:sandbox_organization).of_type("LinkedOrganization")
    expect(subject).to have_field(:self_serve).of_type("Boolean!")
  end
end
