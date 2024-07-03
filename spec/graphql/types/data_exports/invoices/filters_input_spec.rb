# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::DataExports::Invoices::FiltersInput do
  subject { described_class }

  it { is_expected.to accept_argument(:currency).of_type('CurrencyEnum') }
  it { is_expected.to accept_argument(:customer_external_id).of_type('String') }
  it { is_expected.to accept_argument(:invoice_type).of_type('InvoiceTypeEnum') }
  it { is_expected.to accept_argument(:issuing_date_from).of_type('ISO8601Date') }
  it { is_expected.to accept_argument(:issuing_date_to).of_type('ISO8601Date') }
  it { is_expected.to accept_argument(:payment_dispute_lost).of_type('Boolean') }
  it { is_expected.to accept_argument(:payment_overdue).of_type('Boolean') }
  it { is_expected.to accept_argument(:payment_status).of_type('[InvoicePaymentStatusTypeEnum!]') }
  it { is_expected.to accept_argument(:search_term).of_type('String') }
  it { is_expected.to accept_argument(:status).of_type('InvoiceStatusTypeEnum') }
end
