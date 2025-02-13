# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::UsageThresholds::Input do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:id).of_type("ID")
    expect(subject).to accept_argument(:amount_cents).of_type("BigInt")
    expect(subject).to accept_argument(:recurring).of_type("Boolean")
    expect(subject).to accept_argument(:threshold_display_name).of_type("String")
  end
end
