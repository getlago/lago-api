# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ComputeAmountsFromFees, type: :service do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:invoice) { create(:invoice, credit_amount_cents: 100) }

  before do
    create(:fee, invoice:, amount_cents: 151, vat_rate: 10)
    create(:fee, invoice:, amount_cents: 379, vat_rate: 20)
  end

  it 'sets amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :amount_cents).from(0).to(530)
  end

  it 'sets vat_amount_cents from the list of fees' do
    expect { compute_amounts.call }.to change(invoice, :vat_amount_cents).from(0).to(91)
  end

  it 'sets zero to credit_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :credit_amount_cents).from(100).to(0)
  end

  it 'sets total_amount_cents' do
    expect { compute_amounts.call }.to change(invoice, :total_amount_cents).from(0).to(621)
  end

  context 'when credits on invoice' do
    it 'does not set credit_amount_cents' do
      create(:credit, invoice:)
      expect { compute_amounts.call }.not_to change(invoice, :credit_amount_cents).from(100)
    end
  end
end
