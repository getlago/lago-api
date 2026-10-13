# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::EstimateService, :premium do
  subject(:estimate) { described_class.call!(invoice: invoice.reload, items: [{fee_id: fees.last.id, amount_cents: 10}]).credit_note }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:taxes) { [create(:tax, organization:, code: "state", rate: 5), create(:tax, organization:, code: "city", rate: 5)] }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      payment_status: :succeeded,
      fees_amount_cents: 20,
      sub_total_excluding_taxes_amount_cents: 20,
      taxes_amount_cents: 2,
      sub_total_including_taxes_amount_cents: 22,
      total_amount_cents: 22,
      total_paid_amount_cents: 22
    )
  end
  let(:fees) do
    Array.new(2) do |index|
      create(
        :fee,
        invoice:,
        organization:,
        amount_cents: 10,
        precise_amount_cents: 10,
        taxes_amount_cents: 1,
        taxes_precise_amount_cents: 1,
        created_at: index.minutes.from_now
      )
    end
  end

  # Each 0.5c fee row rounds on its own to 1c, while each fee total (1c) and invoice row (1c)
  # rounds once.
  before do
    taxes.each do |tax|
      create(:invoice_applied_tax, invoice:, tax:, tax_code: tax.code, tax_rate: 5, amount_cents: 1, fees_amount_cents: 20)
      fees.each { |fee| create(:fee_applied_tax, fee:, tax:, tax_code: tax.code, tax_rate: 5, amount_cents: 1, precise_amount_cents: 0.5) }
    end
  end

  it "books each fee's own tax" do
    expect(invoice.booked_tax_by_fee).to eq(fees.first => 1, fees.last => 1)
  end

  context "when the first fee was already refunded in full" do
    before do
      CreditNotes::CreateService.call!(invoice:, items: [{fee_id: fees.first.id, amount_cents: 10}], refund_amount_cents: 11)
    end

    it "estimates a full refund of the second fee" do
      expect(estimate.refund_amount_cents).to eq(11)
    end
  end
end
