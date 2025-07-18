# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Entitlement::SubscriptionEntitlementObject do
  subject { described_class }

  it do
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:privileges).of_type("[SubscriptionEntitlementPrivilegeObject!]!")
    expect(subject).to have_field(:removed).of_type("Boolean!")
  end
end
