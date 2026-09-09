# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::QuoteVersions::UpdateInput do
  subject { described_class }

  it "has the expected arguments with correct types" do
    expect(subject).to accept_argument(:billing_entity_id).of_type("ID")
    expect(subject).to accept_argument(:billing_items).of_type("JSON")
    expect(subject).to accept_argument(:content).of_type("String")
    expect(subject).to accept_argument(:currency).of_type("CurrencyEnum")
    expect(subject).to accept_argument(:id).of_type("ID!")
  end
end
