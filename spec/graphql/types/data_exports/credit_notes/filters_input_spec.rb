# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::DataExports::CreditNotes::FiltersInput do
  subject { described_class }

  it { is_expected.to accept_argument(:amount_from).of_type('Int') }
  it { is_expected.to accept_argument(:amount_to).of_type('Int') }
  it { is_expected.to accept_argument(:credit_status).of_type('[CreditNoteCreditStatusEnum!]') }
  it { is_expected.to accept_argument(:currency).of_type('CurrencyEnum') }
  it { is_expected.to accept_argument(:customer_external_id).of_type('String') }
  it { is_expected.to accept_argument(:customer_id).of_type('ID') }
  it { is_expected.to accept_argument(:invoice_number).of_type('String') }
  it { is_expected.to accept_argument(:issuing_date_from).of_type('ISO8601Date') }
  it { is_expected.to accept_argument(:issuing_date_to).of_type('ISO8601Date') }
  it { is_expected.to accept_argument(:reason).of_type('[CreditNoteReasonEnum!]') }
  it { is_expected.to accept_argument(:refund_status).of_type('[CreditNoteRefundStatusEnum!]') }
  it { is_expected.to accept_argument(:search_term).of_type('String') }
end
