# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::QuoteVersions::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization!")
    expect(subject).to have_field(:quote).of_type("Quote!")
    expect(subject).to have_field(:approved_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:billing_items).of_type("JSON")
    expect(subject).to have_field(:content).of_type("String")
    expect(subject).to have_field(:share_token).of_type("String")
    expect(subject).to have_field(:status).of_type("StatusEnum!")
    expect(subject).to have_field(:version).of_type("Int!")
    expect(subject).to have_field(:void_reason).of_type("VoidReasonEnum")
    expect(subject).to have_field(:voided_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end
end
