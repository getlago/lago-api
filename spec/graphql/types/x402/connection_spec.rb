# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::X402::Connection do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:allowed_origins).of_type("[String!]!")
    expect(subject).to have_field(:asset).of_type("X402AssetEnum!")
    expect(subject).to have_field(:auto_create_customers).of_type("Boolean!")
    expect(subject).to have_field(:cdp_api_key_id).of_type("ObfuscatedString").with_permission("organization:integrations:view")
    expect(subject).to have_field(:cdp_api_key_secret).of_type("ObfuscatedString").with_permission("organization:integrations:view")
    expect(subject).to have_field(:facilitator).of_type("X402FacilitatorEnum!")
    expect(subject).to have_field(:networks).of_type("[String!]!")
    expect(subject).to have_field(:payout_addresses).of_type("X402PayoutAddresses!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end
end
