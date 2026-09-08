# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ComputeAmountsFromFees do
  subject(:compute_amounts) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:tax1) { create(:tax, :applied_to_billing_entity, organization:, rate: 10) }
  let(:tax2) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }

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

    expect(fee1.reload.applied_taxes.count).to eq(2)
    expect(fee1.taxes_rate).to eq(30)
    expect(fee1.taxes_amount_cents).to eq(45) # 151 * (10 + 20) / 100

    expect(fee2.reload.applied_taxes.count).to eq(2)
    expect(fee2.taxes_rate).to eq(30)
    expect(fee2.taxes_amount_cents).to eq(84) # (379 - 100) * (10 + 20) / 100
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

  context "when invoice is not persisted and has no persisted fees" do
    subject { described_class.new(invoice: draft_invoice) }

    let(:draft_invoice) { build(:invoice, organization:, customer:, fees: fees) }
    let(:fees) do
      [build(:fee, amount_cents: 100), build(:fee, amount_cents: 150)]
    end

    it "avoids persisting fees" do
      result = subject.call

      expect(result.invoice.fees.length).to eq(2)
      expect(result.invoice.fees.map(&:id)).to eq([nil, nil])
    end

    it "calculates taxes amounts" do
      result = subject.call

      expect(result.invoice.taxes_rate).to eq(30)
    end
  end

  context "when invoice is one_off" do
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :one_off) }

    it "applies taxes to fees regardless of invoice status" do
      compute_amounts.call

      expect(fee1.reload.applied_taxes.count).to eq(2)
      expect(fee1.taxes_rate).to eq(30)
    end

    context "when invoice is pending (deferred tax resolution)" do
      let(:invoice) { create(:invoice, :pending, organization:, customer:, invoice_type: :one_off) }

      it "applies taxes to fees" do
        compute_amounts.call

        expect(fee1.reload.applied_taxes.count).to eq(2)
      end
    end

    context "when invoice is failed" do
      let(:invoice) { create(:invoice, :failed, organization:, customer:, invoice_type: :one_off) }

      it "applies taxes to fees" do
        compute_amounts.call

        expect(fee1.reload.applied_taxes.count).to eq(2)
      end
    end
  end

  context "when invoice is advance_charges" do
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }

    it "does not apply taxes to fees" do
      compute_amounts.call

      expect(fee1.reload.applied_taxes).to be_empty
    end
  end

  context "when taxes are fetched from external provider" do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
    let(:fee2) { create(:fee, invoice: nil) }

    let(:fee_taxes) do
      build(:tax_result,
        item_id: fee1.id,
        item_code: "lago_default_b2b",
        tax_breakdown: [
          build(:tax_breakdown_item, name: "tax 1", type: "type1", rate: "0.50", tax_amount: 75.5),
          build(:tax_breakdown_item, name: "tax 2", type: "type2", rate: "0.30", tax_amount: 45.3)
        ])
    end

    before do
      integration_customer

      invoice.credits.destroy_all
    end

    def three_jurisdiction_taxes(charge, sub_total:, tax_amount_cents:, per_jurisdiction:)
      build(
        :tax_result,
        item_id: "charge_#{charge.id}",
        item_code: "metric_code",
        amount_cents: sub_total,
        tax_amount_cents:,
        tax_breakdown: ["State tax", "County tax", "City tax"].map do |name|
          build(:tax_breakdown_item, name:, type: "tax", rate: "0.025", tax_amount: per_jurisdiction)
        end
      )
    end

    def jurisdiction_amounts(fees)
      fees
        .flat_map { |fee| fee.reload.applied_taxes.to_a }
        .group_by(&:tax_name)
        .transform_values { |taxes| taxes.sum(&:amount_cents) }
    end

    it "creates fee and invoice applied taxes and calculate totals" do
      described_class.new(invoice:, provider_taxes: [fee_taxes]).call

      expect(fee1.reload.applied_taxes.count).to eq(2)
      expect(fee1.taxes_rate).to eq(80)
      expect(fee1.taxes_amount_cents).to eq(121)

      expect(invoice.fees_amount_cents).to eq(151)
      expect(invoice.sub_total_excluding_taxes_amount_cents).to eq(151)
      expect(invoice.taxes_amount_cents).to eq(121)
      expect(invoice.sub_total_including_taxes_amount_cents).to eq(272)
      expect(invoice.taxes_rate).to eq(80)
      expect(invoice.total_amount_cents).to eq(272)
    end

    context "when the provider taxed a charge as a whole" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

      let(:fee1) { create(:charge_fee, invoice:, charge:, amount_cents: 333, precise_amount_cents: 333) }
      let(:fee2) { create(:charge_fee, invoice:, charge:, amount_cents: 333, precise_amount_cents: 333) }
      let(:fee3) { create(:charge_fee, invoice:, charge:, amount_cents: 334, precise_amount_cents: 334) }
      let(:charge_fees) { [fee1, fee2, fee3] }

      let(:group) do
        Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup.new(charge_id: charge.id, fees: charge_fees)
      end
      let(:group_taxes) do
        build(
          :tax_result,
          item_id: "charge_#{charge.id}",
          item_code: "metric_code",
          amount_cents: 1000,
          tax_amount_cents: 100,
          tax_breakdown: [build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount: 100)]
        )
      end

      before { fee3 }

      it "taxes every fee of the charge" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.map { |fee| fee.reload.applied_taxes.count }).to eq([1, 1, 1])
        expect(charge_fees.map(&:taxes_rate)).to eq([10, 10, 10])
      end

      it "settles the rounding difference on the fee that lost the most to it" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.map { |fee| fee.reload.taxes_amount_cents }).to eq([33, 33, 34])
        expect(invoice.fees.reload.sum(&:taxes_amount_cents)).to eq(100)
      end
    end

    context "when the provider taxed a charge across several jurisdictions" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

      let(:fee1) { create(:charge_fee, invoice:, charge:, amount_cents: 268, precise_amount_cents: 268) }
      let(:fee_two) { create(:charge_fee, invoice:, charge:, amount_cents: 25, precise_amount_cents: 25) }
      let(:charge_fees) { [fee1, fee_two] }

      let(:group) do
        Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup.new(charge_id: charge.id, fees: charge_fees)
      end
      let(:group_taxes) do
        build(
          :tax_result,
          item_id: "charge_#{charge.id}",
          item_code: "metric_code",
          amount_cents: 293,
          tax_amount_cents: 24,
          tax_breakdown: [
            build(:tax_breakdown_item, name: "State tax", type: "tax", rate: "0.06", tax_amount: 18),
            build(:tax_breakdown_item, name: "City tax", type: "tax", rate: "0.02", tax_amount: 6)
          ]
        )
      end

      before { fee_two }

      it "keeps the invoice tax equal to the tax of its fees and to the provider amount" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.sum { |fee| fee.reload.taxes_amount_cents }).to eq(24)
        expect(invoice.taxes_amount_cents).to eq(24)
      end

      it "keeps every invoice tax line equal to the fee lines of that jurisdiction" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(invoice.applied_taxes.map { |tax| [tax.tax_name, tax.amount_cents] })
          .to eq([["State tax", 18], ["City tax", 6]])
      end
    end

    context "when a three-jurisdiction charge is split into fifty fees" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

      let(:fee1) { charge_fees.first }
      let(:charge_fees) do
        Array.new(50) { create(:charge_fee, invoice:, charge:, amount_cents: 100, precise_amount_cents: 100) }
      end

      let(:group) do
        Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup.new(charge_id: charge.id, fees: charge_fees)
      end
      let(:group_taxes) { three_jurisdiction_taxes(charge, sub_total: 5000, tax_amount_cents: 375, per_jurisdiction: 125) }

      it "books every fee tax as the sum of its own jurisdiction lines" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        mismatched = charge_fees.reject do |fee|
          fee.reload.applied_taxes.sum(&:amount_cents) == fee.taxes_amount_cents
        end

        expect(mismatched).to be_empty
      end

      it "keeps the charge total equal to the amount the provider returned" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.sum { |fee| fee.reload.taxes_amount_cents }).to eq(375)
        expect(invoice.taxes_amount_cents).to eq(375)
      end

      it "keeps every jurisdiction equal to its breakdown amount" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(jurisdiction_amounts(charge_fees)).to eq({"State tax" => 125, "County tax" => 125, "City tax" => 125})
      end
    end

    context "when a three-jurisdiction charge is split into two fees" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

      let(:fee1) { create(:charge_fee, invoice:, charge:, amount_cents: 100, precise_amount_cents: 100) }
      let(:fee_two) { create(:charge_fee, invoice:, charge:, amount_cents: 100, precise_amount_cents: 100) }
      let(:charge_fees) { [fee1, fee_two] }

      let(:group) do
        Integrations::Aggregator::Taxes::Invoices::ChargeFeeGroup.new(charge_id: charge.id, fees: charge_fees)
      end
      let(:group_taxes) { three_jurisdiction_taxes(charge, sub_total: 200, tax_amount_cents: 15, per_jurisdiction: 5) }

      before { fee_two }

      it "keeps the charge total equal to the amount the provider returned" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.map { |fee| fee.reload.taxes_amount_cents }.sum).to eq(15)
        expect(invoice.taxes_amount_cents).to eq(15)
      end

      it "keeps every jurisdiction equal to its breakdown amount" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(jurisdiction_amounts(charge_fees)).to eq({"State tax" => 5, "County tax" => 5, "City tax" => 5})
      end

      it "books every fee tax as the sum of its own jurisdiction lines" do
        described_class.new(invoice:, provider_taxes: group.split_taxes(group_taxes)).call

        expect(charge_fees.map { |fee| fee.reload.applied_taxes.sum(&:amount_cents) }).to eq([9, 6])
        expect(charge_fees.map(&:taxes_amount_cents)).to eq([9, 6])
      end
    end

    context "when the taxed fees belong to no group" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }

      let(:fee1) { create(:charge_fee, invoice:, charge:, amount_cents: 100, precise_amount_cents: 100) }
      let(:add_on_fee) { create(:add_on_fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }

      let(:ungrouped_taxes) do
        [fee1, add_on_fee].map do |fee|
          build(
            :tax_result,
            item_key: fee.item_key,
            item_id: fee.id,
            item_code: "metric_code",
            amount_cents: 100,
            tax_amount_cents: 8,
            tax_breakdown: [
              build(:tax_breakdown_item, name: "State tax", type: "tax", rate: "0.025", tax_amount: 2.5),
              build(:tax_breakdown_item, name: "County tax", type: "tax", rate: "0.025", tax_amount: 2.5),
              build(:tax_breakdown_item, name: "City tax", type: "tax", rate: "0.025", tax_amount: 2.5)
            ]
          )
        end
      end

      before { add_on_fee }

      it "rounds each fee tax once over its jurisdictions" do
        described_class.new(invoice:, provider_taxes: ungrouped_taxes).call

        expect([fee1, add_on_fee].map { |fee| fee.reload.taxes_amount_cents }).to eq([8, 8])
        expect(jurisdiction_amounts([fee1, add_on_fee]))
          .to eq({"State tax" => 6, "County tax" => 6, "City tax" => 6})
      end

      it "rounds the invoice tax once over its fees" do
        described_class.new(invoice:, provider_taxes: ungrouped_taxes).call

        amounts = invoice.applied_taxes.to_h { |tax| [tax.tax_name, tax.amount_cents] }

        expect(amounts).to eq({"State tax" => 5, "County tax" => 5, "City tax" => 5})
        expect(invoice.taxes_amount_cents).to eq(15)
      end
    end

    context "when provider taxes are not provided" do
      subject(:compute_amounts) { described_class.new(invoice:, provider_taxes: nil) }

      before do
        allow(invoice).to receive(:should_apply_provider_tax?).and_return(true)
        allow(Invoices::ApplyProviderTaxesService).to receive(:call!)
        allow(Invoices::ApplyTaxesService).to receive(:call!).and_call_original
      end

      it "applies regular taxes without fetching provider taxes" do
        compute_amounts.call

        expect(Invoices::ApplyProviderTaxesService).not_to have_received(:call!)
        expect(Invoices::ApplyTaxesService).to have_received(:call!).with(invoice:)
      end
    end
  end
end
