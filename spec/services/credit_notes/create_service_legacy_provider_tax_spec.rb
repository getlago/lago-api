# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateService, :premium do
  let(:invoice) do
    create(
      :invoice,
      payment_status: :succeeded,
      fees_amount_cents: 8,
      sub_total_excluding_taxes_amount_cents: 8,
      taxes_amount_cents:,
      sub_total_including_taxes_amount_cents: 8 + taxes_amount_cents,
      total_amount_cents: 8 + taxes_amount_cents,
      total_paid_amount_cents: 8 + taxes_amount_cents
    )
  end
  let(:fees) do
    Array.new(2) do |index|
      create(
        :fee,
        invoice:,
        amount_cents: 4,
        precise_amount_cents: 4,
        taxes_amount_cents: fee_taxes_amount_cents,
        taxes_precise_amount_cents: fee_taxes_amount_cents,
        created_at: index.minutes.from_now
      )
    end
  end

  context "when every fee tax row rounded up on its own" do
    subject(:refund_rest) do
      described_class.call(invoice:, items: [{fee_id: first_fee.id, amount_cents: 4}], refund_amount_cents: estimate.refund_amount_cents)
    end

    let(:taxes_amount_cents) { 4 }
    let(:fee_taxes_amount_cents) { 2 }
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

  context "when the fee tax rows add up in total but not per jurisdiction" do
    subject(:credit_everything) do
      described_class.call!(invoice:, items: fees.map { |fee| {fee_id: fee.id, amount_cents: 4} }, credit_amount_cents: 10).credit_note
    end

    let(:taxes_amount_cents) { 2 }
    let(:fee_taxes_amount_cents) { 1 }

    # State at 15% owes 0.6c per fee and county at 10% 0.4c: each fee row rounds on its own
    # (1c and 0c), while each invoice row rounds once over both fees (1c and 1c).
    before do
      {"state" => [15, 1, 0.6], "county" => [10, 0, 0.4]}.each do |code, (rate, booked, exact)|
        create(:invoice_applied_tax, invoice:, tax: nil, tax_code: code, tax_rate: rate, amount_cents: 1, fees_amount_cents: 8, taxable_base_amount_cents: 8)
        fees.each { |fee| create(:fee_applied_tax, fee:, tax: nil, tax_code: code, tax_rate: rate, amount_cents: booked, precise_amount_cents: exact) }
      end
    end

    it "credits each jurisdiction what the invoice charged" do
      expect(credit_everything.applied_taxes.to_h { |tax| [tax.tax_code, tax.amount_cents] }).to eq("state" => 1, "county" => 1)
    end
  end
end
