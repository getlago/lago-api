# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::AgentStorefront::PlanInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:plan_code).of_type("String!")
    expect(subject).to accept_argument(:free_credits_cents).of_type("BigInt")
    expect(subject).to accept_argument(:maximum_topup_cents).of_type("BigInt")
    expect(subject).to accept_argument(:minimum_topup_cents).of_type("BigInt")
  end
end
