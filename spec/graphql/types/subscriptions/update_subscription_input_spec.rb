# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Subscriptions::UpdateSubscriptionInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:id).of_type("ID!")
    expect(subject).to accept_argument(:ending_at).of_type("ISO8601DateTime")
    expect(subject).to accept_argument(:name).of_type("String")
    expect(subject).to accept_argument(:plan_overrides).of_type("PlanOverridesInput")
    expect(subject).to accept_argument(:subscription_at).of_type("ISO8601DateTime")
  end
end
