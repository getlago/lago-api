# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CreditNotes::Estimate do
  subject { described_class }

  it { is_expected.to have_field(:currency).of_type("CurrencyEnum!") }
  it { is_expected.to have_field(:taxes_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:sub_total_excluding_taxes_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:max_creditable_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:max_refundable_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:coupons_adjustment_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:taxes_rate).of_type("Float!") }
  it { is_expected.to have_field(:items).of_type("[CreditNoteItemEstimate!]!") }
  it { is_expected.to have_field(:applied_taxes).of_type("[CreditNoteAppliedTax!]!") }
end
