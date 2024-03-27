# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ComputeAmountsFromFees, type: :service do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:tax1) { create(:tax, organization:, rate: 10) }
  let(:tax2) { create(:tax, organization:, rate: 20) }

  let(:fee1) { create(:fee, invoice:, amount_cents: 151) }
  let(:fee2) { create(:fee, invoice:, amount_cents: 379, precise_coupons_amount_cents: 100) }

  before do
    tax1
    tax2

    fee1
    fee2

    create(:credit, invoice:, amount_cents: 100)
  end

  it "applied taxes to the fees" do
    compute_amounts.call

    aggregate_failures do
      expect(fee1.reload.applied_taxes.count).to eq(2)
      expect(fee1.taxes_rate).to eq(30)
      expect(fee1.taxes_amount_cents).to eq(45) # 151 * (10 + 20) / 100

      expect(fee2.reload.applied_taxes.count).to eq(2)
      expect(fee2.taxes_rate).to eq(30)
      expect(fee2.taxes_amount_cents).to eq(84) # (379 - 100) * (10 + 20) / 100
    end
  end

  it "sets fees_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :fees_amount_cents).from(0).to(530)
  end

  it "sets coupons_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :coupons_amount_cents).from(0).to(100)
  end

  it "sets sub_total_excluding_taxes_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :sub_total_excluding_taxes_amount_cents).from(0).to(430)
  end

  it "sets taxes_amount_cents from the list of fees" do
    expect { compute_amounts.call }.to change(invoice, :taxes_amount_cents).from(0).to(129)
  end

  it "sets sub_total_including_taxes_amount_cents" do
    expect { compute_amounts.call }.to change(invoice, :sub_total_including_taxes_amount_cents).from(0).to(559)
  end

  it "sets total_amount_cents" do
    expect { compute_amounts.call }.to change(invoice, :total_amount_cents).from(0).to(559)
  end
end
