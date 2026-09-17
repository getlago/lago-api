# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateService, :premium do
  let(:invoice) do
    create(:invoice, currency: "USD", fees_amount_cents: 10_120, taxes_amount_cents: 891,
      total_amount_cents: 11_011, total_paid_amount_cents: 11_011, payment_status: :succeeded,
      version_number: Invoice::COUPON_BEFORE_VAT_VERSION)
  end
  let(:tax_description) { "tax" }
  let(:taxed_fee) do
    create(:fee, invoice:, amount_cents: 10_040, precise_amount_cents: 10_040,
      amount_currency: "USD", taxes_amount_cents: 891, taxes_rate: 8.875)
  end
  let(:untaxed_fee) do
    create(:fee, invoice:, amount_cents: 80, precise_amount_cents: 80,
      amount_currency: "USD", taxes_amount_cents: 0, taxes_rate: 0)
  end
  let(:items) do
    [
      {fee_id: taxed_fee.id, amount_cents: 10_040},
      {fee_id: untaxed_fee.id, amount_cents: 80}
    ]
  end

  before do
    [taxed_fee, untaxed_fee].each do |fee|
      attributes = {tax: nil, tax_code: "tax", tax_name: "Tax", tax_description:,
                    tax_rate: fee.taxes_rate, amount_cents: fee.taxes_amount_cents, amount_currency: "USD"}
      create(:fee_applied_tax, fee:, **attributes)
      create(:invoice_applied_tax, invoice:, fees_amount_cents: fee.amount_cents,
        taxable_base_amount_cents: fee.amount_cents, **attributes)
    end
  end

  def estimate_and_create_credit_note
    estimate = CreditNotes::EstimateService.call(invoice:, items:)
    expect(estimate).to be_success

    result = CreditNotes::CreateService.call(invoice:, items:,
      credit_amount_cents: estimate.credit_note.credit_amount_cents)
    expect(result).to be_success

    result.credit_note.reload
  end

  it "estimates and creates a full credit without taxing the zero-rate lines" do
    credit_note = estimate_and_create_credit_note

    expect(credit_note).to have_attributes(total_amount_cents: 11_011, taxes_amount_cents: 891)
    expect(credit_note.applied_taxes.order(:tax_rate).pluck(:tax_code, :tax_rate, :base_amount_cents, :amount_cents))
      .to eq([["tax", 0.0, 80, 0], ["tax", 8.875, 10_040, 891]])
    expect(credit_note.items.find_by!(fee: untaxed_fee).applied_taxes.pluck(:tax_rate)).to eq([0.0])
    expect(credit_note.items.find_by!(fee: taxed_fee).applied_taxes.pluck(:tax_rate)).to eq([8.875])
  end

  context "when only the zero-rate lines are credited" do
    let(:items) { [{fee_id: untaxed_fee.id, amount_cents: 80}] }

    it "does not pick the first invoice tax with the same code" do
      credit_note = estimate_and_create_credit_note

      expect(credit_note).to have_attributes(total_amount_cents: 80, taxes_amount_cents: 0)
      expect(credit_note.applied_taxes.pluck(:tax_rate)).to eq([0.0])
    end
  end

  context "when part of each rate group is credited" do
    let(:items) do
      [{fee_id: taxed_fee.id, amount_cents: 5020}, {fee_id: untaxed_fee.id, amount_cents: 40}]
    end

    it "prorates each group independently" do
      credit_note = estimate_and_create_credit_note

      expect(credit_note).to have_attributes(total_amount_cents: 5506, taxes_amount_cents: 446)
      expect(credit_note.applied_taxes.order(:tax_rate).pluck(:base_amount_cents)).to eq([40, 5020])
    end
  end

  context "when the provider tax type is absent" do
    let(:tax_description) { nil }

    it "matches nullable descriptions and persists both rates" do
      credit_note = estimate_and_create_credit_note

      expect(credit_note.total_amount_cents).to eq(11_011)
      expect(credit_note.items.find_by!(fee: untaxed_fee).applied_taxes.pluck(:tax_rate)).to eq([0.0])
    end
  end
end
