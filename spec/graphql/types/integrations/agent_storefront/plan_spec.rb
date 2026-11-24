# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::AgentStorefront::Plan do
  subject { described_class }

  it do
    expect(subject).to have_field(:plan_code).of_type("String!")
    expect(subject).to have_field(:free_credits_cents).of_type("BigInt")
    expect(subject).to have_field(:maximum_topup_cents).of_type("BigInt")
    expect(subject).to have_field(:minimum_topup_cents).of_type("BigInt")
    expect(subject).to have_field(:plan).of_type("Plan")
  end
end
