# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ApplyProviderTaxesService, type: :service do
  subject(:apply_service) { described_class.new(invoice:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      fees_amount_cents:,
      coupons_amount_cents:,
      sub_total_excluding_taxes_amount_cents: fees_amount_cents - coupons_amount_cents
    )
  end
  let(:fees_amount_cents) { 3000 }
  let(:coupons_amount_cents) { 0 }
  let(:result) { BaseService::Result.new }

  let(:fee_taxes) do
    [
      OpenStruct.new(
        tax_breakdown: [
          OpenStruct.new(name: 'tax 1', type: 'type1', rate: '0.10'),
        ]
      ),
      OpenStruct.new(
        tax_breakdown: [
          OpenStruct.new(name: 'tax 1', type: 'type1', rate: '0.10'),
          OpenStruct.new(name: 'tax 2', type: 'type2', rate: '0.12')
        ]
      )
    ]
  end

  describe 'call' do
    before do
      result.fees = fee_taxes
      allow(Integrations::Aggregator::Taxes::Invoices::CreateService).to receive(:call)
        .with(invoice:)
        .and_return(result)
    end

    context 'with non zero fees amount' do
      before do
        fee1 = create(:fee, invoice:, amount_cents: 1000, precise_coupons_amount_cents: 0)
        create(
          :fee_applied_tax,
          fee: fee1,
          amount_cents: 100,
          tax_name: 'tax 1',
          tax_code: 'tax_1',
          tax_rate: 10.0,
          tax_description: 'type1'
        )

        fee2 = create(:fee, invoice:, amount_cents: 2000, precise_coupons_amount_cents: 0)

        create(
          :fee_applied_tax,
          fee: fee2,
          amount_cents: 200,
          tax_name: 'tax 1',
          tax_code: 'tax_1',
          tax_rate: 10.0,
          tax_description: 'type1'
        )
        create(
          :fee_applied_tax,
          fee: fee2,
          amount_cents: 240,
          tax_name: 'tax 2',
          tax_code: 'tax_2',
          tax_rate: 12.0,
          tax_description: 'type2'
        )
      end

      it 'creates applied taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes.find { |item| item.tax_code == 'tax_1' }).to have_attributes(
            invoice:,
            tax_description: 'type1',
            tax_code: 'tax_1',
            tax_name: 'tax 1',
            tax_rate: 10,
            amount_currency: invoice.currency,
            amount_cents: 300,
            fees_amount_cents: 3000
          )

          expect(applied_taxes.find { |item| item.tax_code == 'tax_2' }).to have_attributes(
            invoice:,
            tax_description: 'type2',
            tax_code: 'tax_2',
            tax_name: 'tax 2',
            tax_rate: 12,
            amount_currency: invoice.currency,
            amount_cents: 240,
            fees_amount_cents: 2000
          )

          expect(invoice).to have_attributes(
            taxes_amount_cents: 540,
            taxes_rate: 18,
            fees_amount_cents: 3000
          )
        end
      end
    end

    context 'when invoices fees_amount_cents is zero' do
      let(:fees_amount_cents) { 0 }

      before do
        fee1 = create(:fee, invoice:, amount_cents: 0, precise_coupons_amount_cents: 0)
        create(
          :fee_applied_tax,
          fee: fee1,
          amount_cents: 0,
          tax_name: 'tax 1',
          tax_code: 'tax_1',
          tax_rate: 10.0,
          tax_description: 'type1'
        )

        fee2 = create(:fee, invoice:, amount_cents: 0, precise_coupons_amount_cents: 0)

        create(
          :fee_applied_tax,
          fee: fee2,
          amount_cents: 0,
          tax_name: 'tax 1',
          tax_code: 'tax_1',
          tax_rate: 10.0,
          tax_description: 'type1'
        )
        create(
          :fee_applied_tax,
          fee: fee2,
          amount_cents: 0,
          tax_name: 'tax 2',
          tax_code: 'tax_2',
          tax_rate: 12.0,
          tax_description: 'type2'
        )
      end

      it 'creates applied_taxes' do
        result = apply_service.call

        aggregate_failures do
          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes.find { |item| item.tax_code == 'tax_1' }).to have_attributes(
            invoice:,
            tax_description: 'type1',
            tax_code: 'tax_1',
            tax_name: 'tax 1',
            tax_rate: 10,
            amount_currency: invoice.currency,
            amount_cents: 0,
            fees_amount_cents: 0
          )

          expect(applied_taxes.find { |item| item.tax_code == 'tax_2' }).to have_attributes(
            invoice:,
            tax_description: 'type2',
            tax_code: 'tax_2',
            tax_name: 'tax 2',
            tax_rate: 12,
            amount_currency: invoice.currency,
            amount_cents: 0,
            fees_amount_cents: 0
          )

          expect(invoice).to have_attributes(
            taxes_amount_cents: 0,
            taxes_rate: 16,
            fees_amount_cents: 0
          )
        end
      end
    end
  end
end
