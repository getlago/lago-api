# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentRequests::Object do
  subject { described_class }

  it { is_expected.to have_field(:customer).of_type("Customer!") }
  it { is_expected.to have_field(:invoices).of_type("[Invoice!]!") }

  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:amount_currency).of_type("CurrencyEnum!") }
  it { is_expected.to have_field(:email).of_type("String!") }
  it { is_expected.to have_field(:payment_status).of_type("InvoicePaymentStatusTypeEnum!") }

  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }
end
