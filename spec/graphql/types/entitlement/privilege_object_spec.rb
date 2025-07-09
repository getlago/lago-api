# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Entitlement::PrivilegeObject do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")

    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:config).of_type("JSON!")
    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:value_type).of_type("PrivilegeValueTypeEnum!")
  end
end
