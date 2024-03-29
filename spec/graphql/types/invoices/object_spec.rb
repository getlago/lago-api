# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Invoices::Object do
  subject { described_class }

  it { is_expected.to have_field(:customer).of_type('Customer!') }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:number).of_type('String!') }
  it { is_expected.to have_field(:sequential_id).of_type('ID!') }

  it { is_expected.to have_field(:version_number).of_type('Int!') }

  it { is_expected.to have_field(:invoice_type).of_type('InvoiceTypeEnum!') }
  it { is_expected.to have_field(:payment_dispute_losable).of_type('Boolean!') }
  it { is_expected.to have_field(:payment_dispute_lost_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:payment_status).of_type('InvoicePaymentStatusTypeEnum!') }
  it { is_expected.to have_field(:status).of_type('InvoiceStatusTypeEnum!') }
  it { is_expected.to have_field(:voidable).of_type('Boolean!') }

  it { is_expected.to have_field(:currency).of_type('CurrencyEnum') }
  it { is_expected.to have_field(:taxes_rate).of_type('Float!') }

  it { is_expected.to have_field(:charge_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:coupons_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:credit_notes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:fees_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:prepaid_credit_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:sub_total_excluding_taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:sub_total_including_taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:total_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:issuing_date).of_type('ISO8601Date!') }
  it { is_expected.to have_field(:payment_due_date).of_type('ISO8601Date!') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }

  it { is_expected.to have_field(:creditable_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:refundable_amount_cents).of_type('BigInt!') }

  it { is_expected.to have_field(:file_url).of_type('String') }
  it { is_expected.to have_field(:metadata).of_type('[InvoiceMetadata!]') }

  it { is_expected.to have_field(:applied_taxes).of_type('[InvoiceAppliedTax!]') }
  it { is_expected.to have_field(:credit_notes).of_type('[CreditNote!]') }
  it { is_expected.to have_field(:fees).of_type('[Fee!]') }
  it { is_expected.to have_field(:invoice_subscriptions).of_type('[InvoiceSubscription!]') }
  it { is_expected.to have_field(:subscriptions).of_type('[Subscription!]') }
end
