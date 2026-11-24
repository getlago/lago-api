# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::AgentStorefront::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:code).of_type("String!")
    expect(subject).to accept_argument(:name).of_type("String!")
    expect(subject).to accept_argument(:payment_provider_code).of_type("String!")
    expect(subject).to accept_argument(:plans).of_type("[AgentStorefrontPlanInput!]")
    expect(subject).to accept_argument(:resource_endpoint).of_type("String")
    expect(subject).to accept_argument(:resource_instructions).of_type("String")
  end
end
