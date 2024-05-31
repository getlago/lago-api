# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::CreditNotes::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:number).of_type('String!') }
  it { is_expected.to have_field(:sequential_id).of_type('ID!') }

  it { is_expected.to have_field(:issuing_date).of_type('ISO8601Date!') }

  it { is_expected.to have_field(:description).of_type('String') }
  it { is_expected.to have_field(:reason).of_type('CreditNoteReasonEnum!') }

  it { is_expected.to have_field(:credit_status).of_type('CreditNoteCreditStatusEnum') }
  it { is_expected.to have_field(:refund_status).of_type('CreditNoteRefundStatusEnum') }

  it { is_expected.to have_field(:currency).of_type('CurrencyEnum!') }
  it { is_expected.to have_field(:taxes_rate).of_type('Float!') }

  it { is_expected.to have_field(:balance_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:coupons_adjustment_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:credit_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:refund_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:sub_total_excluding_taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:total_amount_cents).of_type('BigInt!') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:refunded_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:voided_at).of_type('ISO8601DateTime') }

  it { is_expected.to have_field(:file_url).of_type('String') }

  it { is_expected.to have_field(:applied_taxes).of_type('[CreditNoteAppliedTax!]') }
  it { is_expected.to have_field(:customer).of_type('Customer!') }
  it { is_expected.to have_field(:invoice).of_type('Invoice') }
  it { is_expected.to have_field(:items).of_type('[CreditNoteItem!]!') }

  it { is_expected.to have_field(:can_be_voided).of_type('Boolean!') }

  it { is_expected.to have_field(:external_integration_id).of_type('String') }
  it { is_expected.to have_field(:integration_syncable).of_type('Boolean!') }
end
