# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::UserType do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:cs_admin).of_type("Boolean!")
    expect(subject).to have_field(:email).of_type("String")
    expect(subject).to have_field(:premium).of_type("Boolean!")
    expect(subject).to have_field(:memberships).of_type("[Membership!]!")
    expect(subject).to have_field(:needs_organization).of_type("Boolean!")
    expect(subject).to have_field(:organizations).of_type("[Organization!]!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end
end
