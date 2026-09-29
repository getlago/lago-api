# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateService, :premium do
  subject(:refund_rest) do
    described_class.call(invoice:, items: [{fee_id: first_fee.id, amount_cents: 4}], refund_amount_cents: estimate.refund_amount_cents)
  end

  let(:invoice) do
    create(
      :invoice,
      payment_status: :succeeded,
      fees_amount_cents: 8,
      sub_total_excluding_taxes_amount_cents: 8,
      taxes_amount_cents: 4,
      sub_total_including_taxes_amount_cents: 12,
      total_amount_cents: 12,
      total_paid_amount_cents: 12
    )
  end
  let(:fees) do
    Array.new(2) do |index|
      create(
        :fee,
        invoice:,
        amount_cents: 4,
        precise_amount_cents: 4,
        taxes_amount_cents: 2,
        taxes_precise_amount_cents: 2,
        created_at: index.minutes.from_now
      )
    end
  end
  let(:first_fee) { fees.first }
  let(:estimate) { CreditNotes::EstimateService.call!(invoice: invoice.reload, items: [{fee_id: first_fee.id, amount_cents: 4}]).credit_note }

  # Booked like invoices issued before fee amounts were stored: each 0.5c row rounds on its own
  # to 1c, while fee totals (2c) and invoice rows (1c) are rounded once.
  before do
    %w[state county city district].each do |code|
      create(:invoice_applied_tax, invoice:, tax: nil, tax_code: code, tax_rate: 12.5, amount_cents: 1, fees_amount_cents: 8, taxable_base_amount_cents: 8)
      fees.each { |fee| create(:fee_applied_tax, fee:, tax: nil, tax_code: code, tax_rate: 12.5, amount_cents: 1, precise_amount_cents: 0.5) }
    end
    described_class.call!(invoice:, items: [{fee_id: fees.last.id, amount_cents: 4}], refund_amount_cents: 4)
  end

  it "refunds the rest of the invoice at the estimated amount" do
    expect(estimate).to have_attributes(credit_amount_cents: 8, refund_amount_cents: 8)
    expect(refund_rest).to be_success
    expect(invoice.reload.refundable_amount_cents).to eq(0)
  end
end
