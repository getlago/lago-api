# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Taxes::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization")
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:description).of_type("String")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:rate).of_type("Float!")
    expect(subject).to have_field(:applied_to_organization).of_type("Boolean!")
    expect(subject).to have_field(:applied_to_billing_entities_codes).of_type("[String!]!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:add_ons_count).of_type("Int!")
    expect(subject).to have_field(:charges_count).of_type("Int!")
    expect(subject).to have_field(:customers_count).of_type("Int!")
    expect(subject).to have_field(:plans_count).of_type("Int!")
    expect(subject).to have_field(:auto_generated).of_type("Boolean!")
  end
end
