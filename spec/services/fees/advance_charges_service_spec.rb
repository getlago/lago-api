# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::AdvanceChargesService do
  describe ".call" do
    subject(:result) do
      described_class.call(invoice:, billing_contexts:, billing_at:, metered_items:)
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:billing_at) { Time.zone.parse("2026-09-30 23:59:59") }
    let(:metered_items) { [] }

    context "with charge fees" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }
      let(:billing_contexts) { [Billing::Context.from(subscription:)] }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          pay_in_advance: true,
          invoiceable: false,
          regroup_paid_fees: :invoice
        )
      end
      let(:eligible_properties) { {"charges_to_datetime" => (billing_at - 1.day).iso8601(6)} }
      let(:eligible_fee) do
        create_charge_fee(properties: eligible_properties)
      end
      let(:fee_without_charges_to_datetime) do
        create_charge_fee(properties: {})
      end
      let(:excluded_fees) do
        {
          payment_status: create_charge_fee(payment_status: :failed, succeeded_at: nil),
          succeeded_at: create_charge_fee(succeeded_at: billing_at + 1.second),
          invoice: create_charge_fee(invoice: create(:invoice, organization:, customer:)),
          charges_to_datetime: create_charge_fee(
            properties: {"charges_to_datetime" => (billing_at + 1.second).iso8601(6)}
          ),
          subscription: create_charge_fee(subscription: create(:subscription, organization:, customer:, plan:))
        }
      end

      before do
        charge
        eligible_fee
        fee_without_charges_to_datetime
        excluded_fees
      end

      it "attaches only due succeeded fees for the supplied subscriptions" do
        expect(result).to be_success
        expect(invoice.fees.reload).to match_array([eligible_fee, fee_without_charges_to_datetime])
        expect(excluded_fees.transform_values { |fee| fee.reload.invoice_id == invoice.id }).to eq(
          payment_status: false,
          succeeded_at: false,
          invoice: false,
          charges_to_datetime: false,
          subscription: false
        )
      end

      context "when the charge does not regroup paid fees" do
        let(:charge) do
          create(
            :standard_charge,
            plan:,
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: nil
          )
        end

        it "leaves the fees unattached" do
          expect(result).to be_success
          expect(invoice.fees.reload).to be_empty
          expect(eligible_fee.reload.invoice_id).to be_nil
        end
      end
    end

    context "with product fees" do
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
      let(:product) { create(:product, :metered, organization:, billable_metric:) }
      let(:rate_card) do
        create(
          :rate_card,
          :advance,
          :with_filter,
          organization:,
          product:,
          currency: "USD",
          display_on_invoice: false,
          regroup_paid_fees: :invoice
        )
      end
      let(:contract) { create(:contract, organization:, customer:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
      let(:rate_override) { create(:rate_override, organization:) }
      let(:billing_segment) do
        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          rate_card_rate:,
          rate_override:,
          currency: "USD",
          billing_at:,
          cycle_started_at: billing_at.beginning_of_month,
          started_at: billing_at.beginning_of_month,
          ended_at: billing_at,
          status: :processing
        )
      end
      let(:metered_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:) }
      let(:metered_items) { [metered_item] }
      let(:billing_contexts) { [Billing::Context.from(contract:)] }
      let(:eligible_properties) { metered_item.filtered_for_charge_boundaries }
      let(:eligible_fee) { create_product_fee }
      let(:fee_without_charges_to_datetime) do
        create_product_fee(properties: eligible_properties.except("charges_to_datetime"))
      end
      let(:other_contract) { create(:contract, organization:, customer:) }
      let(:other_contract_rate_card) do
        create(:contract_rate_card, organization:, contract: other_contract, rate_card:)
      end
      let(:other_attachment_rate_card) do
        create(
          :rate_card,
          :advance,
          organization:,
          product:,
          product_filter: rate_card.product_filter,
          currency: "USD",
          display_on_invoice: false,
          regroup_paid_fees: :invoice
        )
      end
      let(:other_attachment) do
        create(:contract_rate_card, organization:, contract:, rate_card: other_attachment_rate_card)
      end
      let(:other_product) { create(:product, :metered, organization:, billable_metric:) }
      let(:other_product_filter) { create(:product_filter, organization:, product:) }
      let(:other_rate) { create(:rate_card_rate, organization:, rate_card: other_attachment_rate_card) }
      let(:other_override) { create(:rate_override, organization:) }
      let(:fees_with_ignored_pricing_attributes) do
        [
          create_product_fee(product_filter: other_product_filter),
          create_product_fee(rate_card_rate: other_rate),
          create_product_fee(rate_override: other_override)
        ]
      end
      let(:excluded_fees) do
        {
          contract: create_product_fee(contract: other_contract, contract_rate_card: other_contract_rate_card),
          contract_rate_card: create_product_fee(contract_rate_card: other_attachment),
          invoiceable: create_product_fee(invoiceable: other_product),
          invoice: create_product_fee(invoice: create(:invoice, organization:, customer:)),
          payment_status: create_product_fee(payment_status: :failed, succeeded_at: nil),
          pay_in_advance: create_product_fee(pay_in_advance: false),
          succeeded_at: create_product_fee(succeeded_at: billing_at + 1.second),
          charges_to_datetime: create_product_fee(properties: eligible_properties.merge(
            "charges_to_datetime" => (billing_at + 1.second).iso8601(6)
          ))
        }
      end

      before do
        eligible_fee
        fee_without_charges_to_datetime
        fees_with_ignored_pricing_attributes
        excluded_fees
      end

      it "attaches only fees matching every product and due-date predicate" do
        expect(result).to be_success
        expect(invoice.fees.reload).to match_array([
          eligible_fee,
          fee_without_charges_to_datetime,
          *fees_with_ignored_pricing_attributes
        ])
        expect(result.invoiced_metered_items).to eq([metered_item])
        expect(excluded_fees.transform_values { |fee| fee.reload.invoice_id == invoice.id }).to eq(
          contract: false,
          contract_rate_card: false,
          invoiceable: false,
          invoice: false,
          payment_status: false,
          pay_in_advance: false,
          succeeded_at: false,
          charges_to_datetime: false
        )
      end

      context "when the rate card does not regroup paid fees" do
        let(:rate_card) do
          create(:rate_card, :advance, :with_filter, organization:, product:, currency: "USD")
        end

        it "leaves the product fees unattached" do
          expect(result).to be_success
          expect(invoice.fees.reload).to be_empty
          expect(result.invoiced_metered_items).to eq([])
        end
      end

      context "with several matching metered items" do
        let(:second_product) { create(:product, :metered, organization:, billable_metric:) }
        let(:second_rate_card) do
          create(
            :rate_card,
            :advance,
            organization:,
            product: second_product,
            currency: "USD",
            display_on_invoice: false,
            regroup_paid_fees: :invoice
          )
        end
        let(:second_contract_rate_card) do
          create(:contract_rate_card, organization:, contract:, rate_card: second_rate_card)
        end
        let(:second_rate) { create(:rate_card_rate, organization:, rate_card: second_rate_card) }
        let(:second_segment) do
          create(
            :billing_segment,
            organization:,
            customer:,
            contract:,
            contract_rate_card: second_contract_rate_card,
            rate_card_rate: second_rate,
            currency: "USD",
            billing_at:,
            cycle_started_at: billing_at.beginning_of_month,
            started_at: billing_at.beginning_of_month,
            ended_at: billing_at,
            status: :processing
          )
        end
        let(:second_metered_item) do
          Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: second_segment)
        end
        let(:metered_items) { [metered_item, second_metered_item] }
        let(:second_fee) do
          create(
            :fee,
            :succeeded,
            invoice: nil,
            subscription: nil,
            organization:,
            billing_entity: customer.billing_entity,
            contract:,
            contract_rate_card: second_contract_rate_card,
            rate_card_rate: second_rate,
            invoiceable: second_product,
            product_filter: nil,
            fee_type: :product,
            amount_currency: "USD",
            pay_in_advance: true,
            succeeded_at: billing_at - 1.second,
            properties: second_metered_item.filtered_for_charge_boundaries
          )
        end

        before do
          second_fee
        end

        it "attaches all matches with one combined relation" do
          expect(result).to be_success
          expect(invoice.fees.reload).to include(eligible_fee, second_fee)
          expect(result.invoiced_metered_items).to eq([metered_item, second_metered_item])
        end
      end
    end

    def create_charge_fee(**attributes)
      create(
        :charge_fee,
        :succeeded,
        invoice: nil,
        organization:,
        subscription:,
        charge:,
        succeeded_at: billing_at - 1.second,
        **attributes
      )
    end

    def create_product_fee(**attributes)
      create(
        :fee,
        :succeeded,
        invoice: nil,
        subscription: nil,
        organization:,
        billing_entity: customer.billing_entity,
        contract:,
        contract_rate_card:,
        rate_card_rate:,
        rate_override:,
        invoiceable: product,
        product_filter: rate_card.product_filter,
        fee_type: :product,
        amount_currency: "USD",
        pay_in_advance: true,
        succeeded_at: billing_at - 1.second,
        properties: eligible_properties,
        **attributes
      )
    end
  end
end
