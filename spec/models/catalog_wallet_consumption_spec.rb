# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletConsumption do
  subject(:consumption) { build(:catalog_wallet_consumption) }

  describe "associations" do
    it do
      expect(consumption).to belong_to(:organization)
      expect(consumption).to belong_to(:outbound_transaction).class_name("CatalogWalletTransaction").inverse_of(:fundings)
      expect(consumption).to belong_to(:inbound_transaction).class_name("CatalogWalletTransaction").inverse_of(:consumptions)
      expect(consumption).to belong_to(:fee).optional
    end
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:credit_amount_cents).only_integer.is_greater_than(0) }
  end

  describe "database constraints" do
    let(:existing) { create(:catalog_wallet_consumption) }

    it "refuses a second row for the same entries and fee" do
      duplicate = build(:catalog_wallet_consumption, existing.slice(:inbound_transaction, :outbound_transaction, :fee).symbolize_keys)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a second void row for the same entries" do
      void = create(:catalog_wallet_consumption, fee: nil)
      duplicate = build(:catalog_wallet_consumption, void.slice(:inbound_transaction, :outbound_transaction).symbolize_keys.merge(fee: nil))

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "accepts the same entries on another fee" do
      other_fee = create(:fee, organization: existing.organization, invoice: existing.outbound_transaction.invoice)

      expect(create(:catalog_wallet_consumption, existing.slice(:inbound_transaction, :outbound_transaction).symbolize_keys.merge(fee: other_fee)))
        .to be_persisted
    end
  end
end
