# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ComputeAmountsFromFees, type: :service do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:invoice) { create(:invoice) }

  before do
    create(:fee, invoice:, amount_cents: 151, vat_rate: 10)
    create(:fee, invoice:, amount_cents: 379, vat_rate: 20)
    create(:credit, invoice:, amount_cents: 100)
  end

  it 'sets fees_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :fees_amount_cents).from(0).to(530)
  end

  it 'sets coupons_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :coupons_amount_cents).from(0).to(100)
  end

  it 'sets sub_total_vat_excluded_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :sub_total_vat_excluded_amount_cents).from(0).to(430)
  end

  it 'sets vat_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :vat_amount_cents).from(0).to(74)
  end

  it 'sets sub_total_vat_included_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :sub_total_vat_included_amount_cents).from(0).to(504)
  end

  it 'sets total_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :total_amount_cents).from(0).to(504)
  end
end
