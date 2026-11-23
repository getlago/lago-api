# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::AgentStorefront do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")

    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:payment_provider_code).of_type("String!")
    expect(subject).to have_field(:resource_endpoint).of_type("String")
    expect(subject).to have_field(:resource_instructions).of_type("String")
    expect(subject).to have_field(:scope).of_type("String!")
  end
end
