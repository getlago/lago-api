# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Analytics::InvoiceCollections::Object do
  subject { described_class }

  it { is_expected.to have_field(:month).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:payment_status).of_type('InvoicePaymentStatusTypeEnum') }
  it { is_expected.to have_field(:invoices_count).of_type('BigInt!') }
  it { is_expected.to have_field(:amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:currency).of_type('CurrencyEnum') }
end
