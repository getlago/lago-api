# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: "fee", includes: inclusion) }

  let(:fee) do
    create(
      :fee,
      properties: {
        from_datetime: Time.current,
        to_datetime: Time.current
      }
    )
  end

  let(:inclusion) { [] }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the fee" do
    aggregate_failures do
      expect(result["fee"]).to include(
        "lago_id" => fee.id,
        "lago_charge_id" => fee.charge_id,
        "lago_charge_filter_id" => fee.charge_filter_id,
        "lago_invoice_id" => fee.invoice_id,
        "lago_true_up_fee_id" => fee.true_up_fee&.id,
        "lago_true_up_parent_fee_id" => fee.true_up_parent_fee_id,
        "lago_subscription_id" => fee.subscription_id,
        "external_subscription_id" => fee.subscription&.external_id,
        "lago_customer_id" => fee.customer&.id,
        "external_customer_id" => fee.customer&.external_id,
        "amount_cents" => fee.amount_cents,
        "amount_currency" => fee.amount_currency,
        "taxes_amount_cents" => fee.taxes_amount_cents,
        "taxes_rate" => fee.taxes_rate,
        "total_aggregated_units" => fee.total_aggregated_units,
        "total_amount_cents" => fee.total_amount_cents,
        "total_amount_currency" => fee.amount_currency,
        "precise_amount" => fee.precise_amount_cents.fdiv(100.to_d).to_s,
        "taxes_precise_amount" => fee.taxes_precise_amount_cents.fdiv(100.to_d).to_s,
        "precise_total_amount" => fee.precise_total_amount_cents.fdiv(100.to_d).to_s,
        "units" => fee.units.to_s,
        "precise_unit_amount" => fee.precise_unit_amount.to_s,
        "precise_coupons_amount_cents" => fee.precise_coupons_amount_cents.to_s,
        "pay_in_advance" => fee.subscription.plan.pay_in_advance,
        "invoiceable" => true,
        "events_count" => fee.events_count,
        "payment_status" => fee.payment_status,
        "created_at" => fee.created_at&.iso8601,
        "succeeded_at" => fee.succeeded_at&.iso8601,
        "failed_at" => fee.failed_at&.iso8601,
        "refunded_at" => fee.refunded_at&.iso8601,
        "amount_details" => fee.amount_details,
        "self_billed" => fee.invoice.self_billed,
        "pricing_unit_details" => nil
      )
      expect(result["fee"]["item"]).to include(
        "type" => fee.fee_type,
        "code" => fee.item_code,
        "name" => fee.item_name,
        "description" => fee.item_description,
        "invoice_display_name" => fee.invoice_name,
        "filter_invoice_display_name" => fee.charge_filter&.display_name,
        "filters" => nil,
        "lago_item_id" => fee.item_id,
        "item_type" => fee.item_type,
        "grouped_by" => fee.grouped_by
      )

      expect(result["fee"]["from_date"]).not_to be_nil
      expect(result["fee"]["to_date"]).not_to be_nil
    end
  end

  context "when fee is not attached to an invoice" do
    let(:fee) { create(:fee, invoice: nil) }

    it "serialize self_billed as false" do
      expect(result["fee"]).to include(
        "lago_invoice_id" => nil,
        "self_billed" => false
      )
    end
  end

  context "when fee is charge" do
    let(:charge) { charge_filter.charge }
    let(:charge_filter) { create(:charge_filter) }

    let(:fee) do
      create(
        :charge_fee,
        charge:,
        charge_filter:,
        properties: {
          charges_from_datetime: Time.current,
          charges_to_datetime: Time.current
        }
      )
    end

    it "serializes the fees with dates boundaries" do
      expect(result["fee"]["from_date"]).not_to be_nil
      expect(result["fee"]["to_date"]).not_to be_nil
      expect(result["fee"]["item"]).to include(
        "type" => fee.fee_type,
        "code" => fee.item_code,
        "name" => fee.item_name,
        "invoice_display_name" => fee.invoice_name,
        "filter_invoice_display_name" => fee.filter_display_name,
        "lago_item_id" => fee.item_id,
        "item_type" => fee.item_type
      )
    end

    context "with pay in advance charge" do
      let(:timestamp) { DateTime.new(2023, 12, 13, 0, 0) }
      let(:fee) do
        create(
          :charge_fee,
          charge:,
          properties: {
            charges_from_datetime: (timestamp - 1.month).beginning_of_day,
            charges_to_datetime: (timestamp - 1.day).end_of_day
          }
        )
      end
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice: fee.invoice,
          subscription: fee.subscription,
          timestamp:
        )
      end

      before do
        invoice_subscription
        charge.update!(pay_in_advance: true)
        fee.subscription.update!(
          started_at: timestamp - 1.year,
          billing_time: "anniversary",
          subscription_at: timestamp
        )
      end

      it "serializes the fees with dates boundaries" do
        expect(result["fee"]["from_date"]).to eq("2023-12-13T00:00:00+00:00")
        expect(result["fee"]["to_date"]).to eq("2024-01-12T23:59:59+00:00")
        expect(result["fee"]["item"]).to include(
          "type" => fee.fee_type,
          "code" => fee.item_code,
          "name" => fee.item_name,
          "invoice_display_name" => fee.invoice_name,
          "filter_invoice_display_name" => fee.filter_display_name,
          "lago_item_id" => fee.item_id,
          "item_type" => fee.item_type
        )
      end
    end
  end

  context "when fee is add_on" do
    let(:fee) { create(:add_on_fee) }

    it "does not serializes the fees with date boundaries" do
      expect(result["fee"]["from_date"]).to be_nil
      expect(result["fee"]["to_date"]).to be_nil
    end
  end

  context "when fee is one_off" do
    let(:fee) { create(:one_off_fee) }

    it "does not serializes the fees with date boundaries" do
      expect(result["fee"]["from_date"]).to be_nil
      expect(result["fee"]["to_date"]).to be_nil
    end
  end

  context "when pay_in_advance attributes are included" do
    let(:inclusion) { %i[pay_in_advance] }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, organization:, plan:) }
    let(:charge) { create(:standard_charge, :pay_in_advance, plan:) }

    let(:event) do
      create(
        :event,
        subscription_id: subscription.id,
        organization_id: organization.id,
        customer_id: customer.id
      )
    end

    let(:fee) do
      create(:charge_fee, pay_in_advance: true, subscription:, charge:, pay_in_advance_event_id: event.id, pay_in_advance_event_transaction_id: event.transaction_id)
    end

    it "serializes the pay_in_advance charge attributes" do
      aggregate_failures do
        expect(result["fee"]).to include(
          "lago_subscription_id" => subscription.id,
          "external_subscription_id" => subscription.external_id,
          "lago_customer_id" => customer.id,
          "external_customer_id" => customer.external_id,
          "event_transaction_id" => fee.pay_in_advance_event_transaction_id,
          "pay_in_advance" => true,
          "invoiceable" => true
        )
      end
    end
  end

  context "when pricing_unit_usage attributes are included" do
    let!(:pricing_unit_usage) { create(:pricing_unit_usage, fee:) }

    it "serializes the pricing_unit_usage" do
      expect(result["fee"]["pricing_unit_details"]).to be_present
      expect(result["fee"]["pricing_unit_details"]).to include(
        "lago_pricing_unit_id" => pricing_unit_usage.pricing_unit_id,
        "short_name" => pricing_unit_usage.short_name,
        "amount_cents" => pricing_unit_usage.amount_cents
      )
    end
  end
end
