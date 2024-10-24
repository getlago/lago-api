# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::SyncCrmInvoiceInput do
  subject { described_class }

  it { is_expected.to accept_argument(:invoice_id).of_type('ID!') }
end
