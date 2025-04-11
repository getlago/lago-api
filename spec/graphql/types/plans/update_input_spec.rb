# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Plans::UpdateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:id).of_type("ID!")
    expect(subject).to accept_argument(:amount_cents).of_type("BigInt!")
    expect(subject).to accept_argument(:amount_currency).of_type("CurrencyEnum!")
    expect(subject).to accept_argument(:bill_charges_monthly).of_type("Boolean")
    expect(subject).to accept_argument(:cascade_updates).of_type("Boolean")
    expect(subject).to accept_argument(:code).of_type("String!")
    expect(subject).to accept_argument(:description).of_type("String")
    expect(subject).to accept_argument(:interval).of_type("PlanInterval!")
    expect(subject).to accept_argument(:invoice_display_name).of_type("String")
    expect(subject).to accept_argument(:name).of_type("String!")
    expect(subject).to accept_argument(:pay_in_advance).of_type("Boolean!")
    expect(subject).to accept_argument(:tax_codes).of_type("[String!]")
    expect(subject).to accept_argument(:trial_period).of_type("Float")

    expect(subject).to accept_argument(:charges).of_type("[ChargeInput!]!")
    expect(subject).to accept_argument(:minimum_commitment).of_type("CommitmentInput")
    expect(subject).to accept_argument(:usage_thresholds).of_type("[UsageThresholdInput!]")
  end
end
