# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::X402::Network do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:family).of_type("X402NetworkFamilyEnum!")
    expect(subject).to have_field(:environment).of_type("X402NetworkEnvironmentEnum!")
  end
end
