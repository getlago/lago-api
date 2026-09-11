# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ReconcileGroupedProviderTaxesService do
  subject(:reconcile_service) { described_class.new(fees:, provider_taxes:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:group_key) { "charge_#{SecureRandom.uuid}" }
  let(:group_tax_amount_cents) { 100 }

  let(:fees) { [fee1, fee2, fee3] }

  let(:fee1) { create_taxed_fee(amount_cents: 333, taxes_amount_cents: 33, taxes_precise_amount_cents: 33.3) }
  let(:fee2) { create_taxed_fee(amount_cents: 333, taxes_amount_cents: 33, taxes_precise_amount_cents: 33.3) }
  let(:fee3) { create_taxed_fee(amount_cents: 334, taxes_amount_cents: 33, taxes_precise_amount_cents: 33.4) }

  let(:provider_taxes) do
    fees.map do |fee|
      build(:tax_result, item_key: fee.item_key, item_id: fee.id, group_key:, group_tax_amount_cents:)
    end
  end

  def create_taxed_fee(amount_cents:, taxes_amount_cents:, taxes_precise_amount_cents:)
    fee = create(
      :charge_fee,
      invoice:,
      organization:,
      amount_cents:,
      precise_amount_cents: amount_cents,
      taxes_amount_cents:,
      taxes_precise_amount_cents:
    )
    create(
      :fee_applied_tax,
      fee:,
      organization:,
      tax_code: "vat",
      tax_rate: 10.0,
      amount_cents: taxes_amount_cents,
      precise_amount_cents: taxes_precise_amount_cents
    )
    fee.reload
  end

  describe "#call" do
    it "adds the missing cent to the fee that lost the most to rounding" do
      result = reconcile_service.call

      expect(result).to be_success
      expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 33, 34])
    end

    it "keeps the applied tax consistent with the fee" do
      reconcile_service.call

      expect(fee3.reload.applied_taxes.sole.amount_cents).to eq(34)
    end

    it "leaves the precise amounts untouched" do
      reconcile_service.call

      expect(fee3.reload.taxes_precise_amount_cents).to eq(33.4)
      expect(fee3.applied_taxes.sole.precise_amount_cents).to eq(33.4)
    end

    it "makes the group total match the amount the provider returned" do
      reconcile_service.call

      expect(fees.sum { |fee| fee.reload.taxes_amount_cents }).to eq(group_tax_amount_cents)
    end

    context "when the fees add up to more than the provider returned" do
      let(:group_tax_amount_cents) { 98 }

      it "removes the extra cent from the fee that gained the most from rounding" do
        fee2.update!(taxes_precise_amount_cents: 32.9)

        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 32, 33])
      end
    end

    context "when every fee lost a cent to rounding" do
      let(:group_tax_amount_cents) { 102 }

      it "gives a cent to each of them" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([34, 34, 34])
      end
    end

    context "when the difference is larger than one cent per fee" do
      let(:group_tax_amount_cents) { 104 }

      it "keeps handing out cents until the difference is gone" do
        reconcile_service.call

        amounts = fees.map { |fee| fee.reload.taxes_amount_cents }

        expect(amounts.sum).to eq(104)
        expect(amounts.sort).to eq([34, 35, 35])
      end
    end

    context "when the provider taxed a group less than the fees did and one of them has no tax" do
      let(:fee2) { create_taxed_fee(amount_cents: 333, taxes_amount_cents: 33, taxes_precise_amount_cents: 32.9) }
      let(:fee3) { create_taxed_fee(amount_cents: 334, taxes_amount_cents: 0, taxes_precise_amount_cents: 0) }
      let(:group_tax_amount_cents) { 65 }

      it "never drives an applied tax below zero" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 32, 0])
        expect(fees.map { |fee| fee.applied_taxes.sole.amount_cents }).to eq([33, 32, 0])
      end
    end

    context "when the absorbing fee also carries a zero-rate special taxation line" do
      let(:fees) { [fee1, fee2] }
      let(:fee1) { create_exempt_fee(amount_cents: 4, taxes_precise_amount_cents: 0.4) }
      let(:fee2) { create_taxed_fee(amount_cents: 996, taxes_amount_cents: 99, taxes_precise_amount_cents: 99.2) }

      def create_exempt_fee(amount_cents:, taxes_precise_amount_cents:)
        fee = create(
          :charge_fee,
          invoice:,
          organization:,
          amount_cents:,
          precise_amount_cents: amount_cents,
          taxes_amount_cents: 0,
          taxes_precise_amount_cents:
        )
        create(
          :fee_applied_tax,
          fee:,
          organization:,
          tax_code: "gst_hst",
          tax_rate: 10.0,
          amount_cents: 0,
          precise_amount_cents: taxes_precise_amount_cents
        )
        create(
          :fee_applied_tax,
          fee:,
          organization:,
          tax_code: "reverse_charge",
          tax_rate: 0.0,
          amount_cents: 0,
          precise_amount_cents: 0
        )
        fee.reload
      end

      it "books the cent on the jurisdiction that taxes the fee" do
        reconcile_service.call

        amounts = fee1.reload.applied_taxes.pluck(:tax_code, :amount_cents).to_h

        expect(amounts).to eq({"gst_hst" => 1, "reverse_charge" => 0})
      end
    end

    context "when fewer fees carry tax than the difference to remove" do
      let(:fee1) { create_taxed_fee(amount_cents: 0, taxes_amount_cents: 0, taxes_precise_amount_cents: 0) }
      let(:fee2) { create_taxed_fee(amount_cents: 0, taxes_amount_cents: 0, taxes_precise_amount_cents: 0) }
      let(:fee3) { create_taxed_fee(amount_cents: 1000, taxes_amount_cents: 13, taxes_precise_amount_cents: 13) }
      let(:group_tax_amount_cents) { 10 }

      it "takes the whole difference from the only fee that can absorb it" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([0, 0, 10])
      end
    end

    context "when the difference asks for more than some fees can give" do
      let(:fee3) { create_taxed_fee(amount_cents: 0, taxes_amount_cents: 0, taxes_precise_amount_cents: 0) }
      let(:group_tax_amount_cents) { 0 }

      it "keeps taking from the others without driving any of them below zero" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([0, 0, 0])
        expect(fees.map { |fee| fee.applied_taxes.sole.amount_cents }).to eq([0, 0, 0])
      end
    end

    context "when the fees already add up to the provider amount" do
      let(:group_tax_amount_cents) { 99 }

      it "changes nothing" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 33, 33])
      end
    end

    context "when fees of the same amount lose the same to rounding" do
      let(:fee3) { create_taxed_fee(amount_cents: 333, taxes_amount_cents: 33, taxes_precise_amount_cents: 33.3) }
      let(:group_tax_amount_cents) { 100 }

      it "picks the same fee on every run" do
        expected = fees.min_by { |fee| fee.item_key }

        reconcile_service.call

        expect(fees.select { |fee| fee.reload.taxes_amount_cents == 34 }).to eq([expected])
      end
    end

    context "when the results belong to no group" do
      let(:provider_taxes) do
        fees.map { |fee| build(:tax_result, item_key: fee.item_key, item_id: fee.id, tax_amount_cents: 40) }
      end

      it "changes nothing" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 33, 33])
      end
    end

    context "when a group holds a single fee" do
      let(:provider_taxes) do
        [build(:tax_result, item_key: fee1.item_key, item_id: fee1.id, group_key:, group_tax_amount_cents: 40)]
      end

      it "changes nothing" do
        reconcile_service.call

        expect(fee1.reload.taxes_amount_cents).to eq(33)
      end
    end

    context "when a member fee is missing from the fees" do
      let(:fees) { [fee1, fee2] }
      let(:provider_taxes) do
        [fee1, fee2, fee3].map do |fee|
          build(:tax_result, item_key: fee.item_key, item_id: fee.id, group_key:, group_tax_amount_cents:)
        end
      end

      it "leaves the group alone" do
        reconcile_service.call

        expect(fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 33])
      end
    end

    context "when the fees are not persisted" do
      let(:fee1) { build_taxed_fee(taxes_amount_cents: 33, taxes_precise_amount_cents: 33.3) }
      let(:fee2) { build_taxed_fee(taxes_amount_cents: 33, taxes_precise_amount_cents: 33.3) }
      let(:fee3) { build_taxed_fee(taxes_amount_cents: 33, taxes_precise_amount_cents: 33.4) }

      def build_taxed_fee(taxes_amount_cents:, taxes_precise_amount_cents:)
        fee = build(:charge_fee, invoice:, organization:, taxes_amount_cents:, taxes_precise_amount_cents:)
        fee.applied_taxes << build(
          :fee_applied_tax,
          fee:,
          organization:,
          tax_code: "vat",
          amount_cents: taxes_amount_cents,
          precise_amount_cents: taxes_precise_amount_cents
        )
        fee
      end

      it "adjusts them in memory without saving" do
        reconcile_service.call

        expect(fees.map(&:taxes_amount_cents)).to eq([33, 33, 34])
        expect(fees.map(&:persisted?)).to eq([false, false, false])
      end
    end
  end
end
