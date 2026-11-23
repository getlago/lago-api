# frozen_string_literal: true

require "rails_helper"

describe CatalogWallets::ApplyTaxesService do
  subject(:result) { described_class.call(wallet:, tax_codes:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:tax1) { create(:tax, organization:) }
  let_it_be(:tax2) { create(:tax, organization:) }

  let(:wallet) { create(:plan_wallet, organization:) }
  let(:tax_codes) { [tax1.code, tax2.code] }

  it "applies the organization taxes to the wallet" do
    expect { result }.to change(wallet.applied_taxes, :count).from(0).to(2)

    expect(result).to be_success
    expect(result.applied_taxes.map(&:tax)).to match_array([tax1, tax2])
    expect(wallet.reload.taxes).to match_array([tax1, tax2])
    expect(wallet.applied_taxes.map { [it.organization_id, it.plan_wallet_id, it.catalog_wallet_id] }.uniq)
      .to eq([[organization.id, wallet.id, nil]])
  end

  context "when the wallet belongs to a contract" do
    let(:wallet) { create(:catalog_wallet, organization:) }
    let(:tax_codes) { [tax1.code] }

    it "applies the tax to the contract wallet" do
      expect(result).to be_success
      expect(result.applied_taxes.sole).to have_attributes(catalog_wallet_id: wallet.id, plan_wallet_id: nil, tax_id: tax1.id)
    end
  end

  context "when tax codes contain duplicates" do
    let(:tax_codes) { [tax1.code, tax1.code] }

    it "applies the tax once" do
      expect { result }.to change(wallet.applied_taxes, :count).from(0).to(1)

      expect(result).to be_success
      expect(result.applied_taxes.map(&:tax)).to eq([tax1])
    end
  end

  context "when the wallet already has taxes" do
    let(:tax_codes) { [tax2.code] }

    before do
      create(:catalog_wallet_applied_tax, :plan_level, plan_wallet: wallet, tax: tax1, organization:)
      wallet.taxes.load
    end

    it "replaces them and resets the loaded association" do
      expect { result }.not_to change(wallet.applied_taxes, :count)

      expect(result).to be_success
      expect(wallet.taxes).to eq([tax2])
    end

    context "when tax codes are empty" do
      let(:tax_codes) { [] }

      it "removes every tax" do
        expect { result }.to change(wallet.applied_taxes, :count).from(1).to(0)

        expect(result).to be_success
        expect(result.applied_taxes).to be_empty
      end
    end

    context "when a tax code does not exist" do
      let(:tax_codes) { [tax2.code, "unknown"] }

      it "returns a tax not found failure without changing the taxes" do
        expect { result }.not_to change { wallet.applied_taxes.pluck(:tax_id) }

        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
      end
    end
  end

  context "when the tax belongs to another organization" do
    let(:tax_codes) { [create(:tax, organization: create(:organization)).code] }

    it "returns a tax not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("tax")
    end
  end

  context "when the wallet does not exist" do
    let(:wallet) { nil }

    it "returns a wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
    end
  end
end
