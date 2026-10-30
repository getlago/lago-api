# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::X402::Settlement do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:asset).of_type("X402AssetEnum!")
    expect(subject).to have_field(:credit_amount).of_type("String")
    expect(subject).to have_field(:kind).of_type("X402SettlementKindEnum!")
    expect(subject).to have_field(:network).of_type("String!")
    expect(subject).to have_field(:payee_address).of_type("String!")
    expect(subject).to have_field(:payer_address).of_type("String!")
    expect(subject).to have_field(:settled_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:status).of_type("X402SettlementStatusEnum!")
  end
end
