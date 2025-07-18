# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Entitlement::SubscriptionEntitlementPrivilegeObject do
  subject { described_class }

  it do
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:value).of_type("String!")
  end
end
