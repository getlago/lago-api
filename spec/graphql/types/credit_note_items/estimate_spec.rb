# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CreditNoteItems::Estimate do
  subject { described_class }

  it { is_expected.to have_field(:amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:fee).of_type("Fee!") }
end
