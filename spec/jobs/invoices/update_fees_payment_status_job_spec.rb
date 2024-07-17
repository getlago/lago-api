# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::UpdateFeesPaymentStatusJob, type: :job do
  # Still investigating why this trait didn't get renamed
  let(:invoice) { create(:invoice, :succeeded) }
  let(:fee) { create(:fee, invoice:) }

  before { fee }

  it 'updates the payment_status of the fee' do
    described_class.perform_now(invoice)

    expect(fee.reload.payment_status).to eq('succeeded')
  end
end
