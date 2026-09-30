# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::BaseService do
  [
    Integrations::Aggregator::Taxes::Invoices::CreateDraftService,
    Integrations::Aggregator::Taxes::Invoices::CreateService
  ].product(%i[anrok avalara]).each do |service_class, provider|
    describe "#{service_class}#call with #{provider}" do
      subject(:service_result) { service_class.call(invoice:, fees:) }

      let(:invoice) { create(:invoice) }
      let(:customer) { invoice.customer }
      let(:integration) { create(:"#{provider}_integration", organization: invoice.organization) }
      let(:charge) { create(:standard_charge, organization: invoice.organization) }
      let(:created_at) { Time.current.change(usec: 0) }
      let(:amount_cents) { 100 }
      let(:first_fee) do
        create(:charge_fee, invoice:, charge:, amount_cents:, precise_amount_cents: amount_cents, units: 1,
          created_at:, id: "00000000-0000-4000-8000-000000000001")
      end
      let(:second_fee) do
        create(:charge_fee, invoice:, charge:, amount_cents:, precise_amount_cents: amount_cents, units: 1,
          created_at:, id: "00000000-0000-4000-8000-000000000002")
      end
      let(:fees) { [second_fee, first_fee] }
      let(:requested_items) { [] }
      let(:fee_taxes) { (provider == :anrok) ? [3, 2] : [5, 5] }

      before do
        create(:"#{provider}_customer", integration:, customer:)
        create(:netsuite_collection_mapping, integration:, mapping_type: :fallback_item,
          settings: {external_id: "1", external_account_code: "11", external_name: ""})
        second_fee
        first_fee

        stub_request(:post, %r{https://api.nango.dev/v1/#{provider}/(draft|finalized)_invoices}).to_return do |request|
          items = JSON.parse(request.body).first.fetch("fees")
          requested_items.concat(items)
          taxed_items = items.map do |item|
            item.merge("tax_amount_cents" => 5, "tax_breakdown" => [
              {"name" => "VAT", "type" => "tax", "rate" => "0.025", "tax_amount" => 5}
            ])
          end

          {body: {succeededInvoices: [{id: "invoice", fees: taxed_items}], failedInvoices: []}.to_json}
        end
      end

      it "orders fees by ID when timestamps are equal" do
        expect(service_result).to be_success
        expect(service_result.fees.map { |tax| [tax.item_key, tax.tax_amount_cents] })
          .to eq([[first_fee.item_key, fee_taxes[0]], [second_fee.item_key, fee_taxes[1]]])
      end

      if provider == :anrok
        it "sends one charge line with the combined amount" do
          service_result

          expect(requested_items).to eq(
            [{"item_key" => charge.id, "item_id" => charge.id, "item_code" => "1", "amount_cents" => 200}]
          )
        end
      else
        it "sends one line per fee, since Avalara rounds tax per line" do
          service_result

          expect(requested_items).to eq(
            [first_fee, second_fee].map do |fee|
              {"item_key" => fee.item_key, "item_id" => fee.id, "item_code" => "1", "unit" => "1.0", "amount" => "1.0"}
            end
          )
        end
      end

      context "with a singleton charge and an unrelated fee" do
        let(:other_fee) { create(:add_on_fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }
        let(:fees) { [first_fee, other_fee] }

        it "preserves individual identities in the payload and response" do
          expect(service_result.fees.map { |tax| [tax.item_id, tax.tax_amount_cents] })
            .to eq([[first_fee.id, 5], [other_fee.id, 5]])
          expect(requested_items.map { |item| item.fetch("item_key") }).to eq([first_fee.item_key, other_fee.item_key])
        end
      end

      context "with a grouped charge and an unrelated fee" do
        let(:other_fee) { create(:add_on_fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }
        let(:fees) { [second_fee, first_fee, other_fee] }

        it "splits only the grouped response" do
          expect(service_result.fees.map { |tax| [tax.item_id, tax.tax_amount_cents] })
            .to eq([[first_fee.id, fee_taxes[0]], [second_fee.id, fee_taxes[1]], [other_fee.id, 5]])
          expect(requested_items.size).to eq((provider == :anrok) ? 2 : 3)
        end
      end

      if provider == :avalara
        context "when the invoice is voided" do
          let(:invoice) { create(:invoice, status: :voided) }

          it "negates each fee amount" do
            service_result

            expect(requested_items.map { |item| item.fetch("amount") }).to eq(["-1.0", "-1.0"])
          end
        end
      end

      context "when fees come from the invoice association" do
        let(:fees) { nil }

        it "allocates in the same order as an explicitly supplied array" do
          expect(service_result.fees.map { |tax| [tax.item_key, tax.tax_amount_cents] })
            .to eq([[first_fee.item_key, fee_taxes[0]], [second_fee.item_key, fee_taxes[1]]])
        end
      end

      context "when creation times differ" do
        let(:second_fee) do
          create(:charge_fee, invoice:, charge:, amount_cents:, precise_amount_cents: amount_cents,
            created_at: created_at - 1.second, id: "00000000-0000-4000-8000-000000000002")
        end

        it "orders by creation time before ID" do
          expect(service_result.fees.map { |tax| [tax.item_key, tax.tax_amount_cents] })
            .to eq([[second_fee.item_key, fee_taxes[0]], [first_fee.item_key, fee_taxes[1]]])
        end
      end

      context "when all fees are untaxable" do
        let(:amount_cents) { 0 }

        it "uses the same first fee as the invoice stand-in" do
          service_result

          expect(requested_items.map { |item| item.fetch("item_id") }).to eq([first_fee.id])
        end
      end

      context "when fees are not persisted" do
        let(:first_fee) { build(:charge_fee, invoice:, charge:, amount_cents:, precise_amount_cents: amount_cents) }
        let(:second_fee) { build(:charge_fee, invoice:, charge:, amount_cents:, precise_amount_cents: amount_cents) }

        it "preserves generation order without requiring IDs or timestamps" do
          expect(service_result.fees.map { |tax| [tax.item_key, tax.tax_amount_cents] })
            .to eq([[second_fee.item_key, fee_taxes[0]], [first_fee.item_key, fee_taxes[1]]])
        end
      end
    end
  end
end
