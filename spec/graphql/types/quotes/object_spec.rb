# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization!")
    expect(subject).to have_field(:customer).of_type("Customer!")

    expect(subject).to have_field(:approved_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:auto_execute).of_type("Boolean!")
    expect(subject).to have_field(:backdated_billing).of_type("QuoteBackdatedBillingEnum")
    expect(subject).to have_field(:billing_items).of_type("JSON")
    expect(subject).to have_field(:commercial_terms).of_type("JSON")
    expect(subject).to have_field(:contacts).of_type("JSON")
    expect(subject).to have_field(:content).of_type("String")
    expect(subject).to have_field(:currency).of_type("String")
    expect(subject).to have_field(:description).of_type("String")
    expect(subject).to have_field(:execution_mode).of_type("QuoteExecutionModeEnum")
    expect(subject).to have_field(:internal_notes).of_type("String")
    expect(subject).to have_field(:legal_text).of_type("String")
    expect(subject).to have_field(:metadata).of_type("JSON")
    expect(subject).to have_field(:number).of_type("String!")
    expect(subject).to have_field(:order_type).of_type("QuoteOrderTypeEnum!")
    expect(subject).to have_field(:owners).of_type("[User!]")
    expect(subject).to have_field(:share_token).of_type("String")
    expect(subject).to have_field(:status).of_type("QuoteStatusEnum!")
    expect(subject).to have_field(:version).of_type("Int!")
    expect(subject).to have_field(:void_reason).of_type("QuoteVoidReasonEnum")
    expect(subject).to have_field(:voided_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
  end
end
