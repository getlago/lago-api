# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::ApplyTaxesService do
  subject(:result) { described_class.call(rate_card:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:tax1) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:) }
  let(:tax_codes) { [tax1.code, tax2.code] }

  it "applies the organization taxes to the rate card" do
    expect { result }.to change(rate_card.applied_taxes, :count).from(0).to(2)

    expect(result).to be_success
    expect(result.applied_taxes.map(&:tax)).to match_array([tax1, tax2])
    expect(rate_card.reload.taxes).to match_array([tax1, tax2])
    expect(rate_card.applied_taxes.pluck(:organization_id).uniq).to eq([organization.id])
  end

  it "locks the rate card while replacing taxes" do
    allow(rate_card).to receive(:with_lock).and_call_original

    result

    expect(rate_card).to have_received(:with_lock)
  end

  context "when the rate card is used by an invoice fee" do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:invoice) { create(:invoice, organization:, customer:, status: invoice_status) }
    let(:invoice_status) { :draft }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }

    before do
      create(:product_fee, invoice:, subscription:, rate_card_rate:)
    end

    it "marks a draft invoice for refresh and updates its timestamp when the assignments change" do
      invoice.update!(updated_at: 1.day.ago)
      previous_updated_at = invoice.updated_at

      result

      expect(invoice.reload.ready_to_be_refreshed).to be(true)
      expect(invoice.updated_at).to be > previous_updated_at
    end

    it "does not mark a draft invoice when the assignments do not change" do
      create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:)
      create(:rate_card_applied_tax, rate_card:, tax: tax2, organization:)

      expect { result }.not_to change { invoice.reload.ready_to_be_refreshed }
    end

    context "when every assignment is removed" do
      let(:tax_codes) { [] }

      before do
        create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:)
      end

      it "marks a draft invoice for refresh" do
        expect { result }.to change { invoice.reload.ready_to_be_refreshed }.from(false).to(true)
      end
    end

    context "when the invoice is finalized" do
      let(:invoice_status) { :finalized }

      it "does not mark the invoice for refresh" do
        expect { result }.not_to change { invoice.reload.ready_to_be_refreshed }
      end
    end
  end

  context "when tax codes contain duplicates" do
    let(:tax_codes) { [tax1.code, tax1.code] }

    it "applies the tax once" do
      expect { result }.to change(rate_card.applied_taxes, :count).from(0).to(1)

      expect(result).to be_success
      expect(result.applied_taxes.map(&:tax)).to eq([tax1])
    end
  end

  context "when the rate card already has taxes" do
    before do
      create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:)
      rate_card.taxes.load
    end

    let(:tax_codes) { [tax2.code] }

    it "replaces the existing taxes" do
      expect { result }.not_to change(rate_card.applied_taxes, :count)

      expect(result).to be_success
      expect(rate_card.taxes).to eq([tax2])
    end
  end

  context "when tax codes are empty" do
    before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

    let(:tax_codes) { [] }

    it "removes all taxes" do
      expect { result }.to change(rate_card.applied_taxes, :count).from(1).to(0)

      expect(result).to be_success
      expect(result.applied_taxes).to be_empty
    end
  end

  context "when a tax code does not exist" do
    let(:tax_codes) { [tax1.code, "unknown"] }

    it "returns a tax not found failure without changing assignments" do
      expect { result }.not_to change(rate_card.applied_taxes, :count)

      expect(result).not_to be_success
      expect(result.error.resource).to eq("tax")
    end
  end

  context "when the tax belongs to another organization" do
    let(:other_tax) { create(:tax) }
    let(:tax_codes) { [other_tax.code] }

    it "returns a tax not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("tax")
    end
  end

  context "when the rate card is nil" do
    let(:rate_card) { nil }

    it "returns a rate card not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end
end
