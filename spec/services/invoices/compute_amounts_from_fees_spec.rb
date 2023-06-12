# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ComputeAmountsFromFees, type: :service do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, organization:) }

  let(:tax1) { create(:tax, organization:, rate: 10) }
  let(:tax2) { create(:tax, organization:, rate: 20) }

  before do
    fee1 = create(:fee, invoice:, amount_cents: 151, taxes_rate: 10)
    create(:fee_applied_tax, fee: fee1, tax: tax1, amount_cents: 151, tax_rate: 10)

    fee2 = create(:fee, invoice:, amount_cents: 379, taxes_rate: 20)
    create(:fee_applied_tax, fee: fee2, tax: tax2, amount_cents: 379, tax_rate: 20)

    create(:credit, invoice:, amount_cents: 100)
  end

  it 'sets fees_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :fees_amount_cents).from(0).to(530)
  end

  it 'sets coupons_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :coupons_amount_cents).from(0).to(100)
  end

  it 'sets sub_total_excluding_taxes_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :sub_total_excluding_taxes_amount_cents).from(0).to(430)
  end

  it 'sets taxes_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :taxes_amount_cents).from(0).to(74)
  end

  it 'sets sub_total_including_taxes_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :sub_total_including_taxes_amount_cents).from(0).to(504)
  end

  it 'sets total_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :total_amount_cents).from(0).to(504)
  end
end
