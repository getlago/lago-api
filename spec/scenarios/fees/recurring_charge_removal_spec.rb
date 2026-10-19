# frozen_string_literal: true

require "rails_helper"

# A customer pays a monthly price for each phone number until the number is removed.
# The numbers are tracked with a recurring billable metric: one event adds a number,
# another event removes it, and no event is needed in the months where nothing changes.
# The price depends on the number type, set with a charge filter.
describe "Recurring charges stopped with an event" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:prorated) { false }
  let(:pricing_group_keys) { nil }
  let(:subscription) { customer.subscriptions.sole }

  def send_number_event(number_id, number_type, extra_properties)
    create_event(
      {
        code: "phone_numbers",
        external_subscription_id: "sub_phone_numbers",
        properties: {number_id:, number_type:, **extra_properties}
      }
    )
  end

  def charge_amounts(issuing_date)
    invoice = subscription.invoices.find_by!(issuing_date:)
    invoice.fees.charge.to_h { [it.charge_filter&.invoice_display_name, it.amount_cents] }
  end

  def grouped_charge_amounts(issuing_date)
    invoice = subscription.invoices.find_by!(issuing_date:)
    invoice.fees.charge.map { [it.charge_filter&.invoice_display_name, it.grouped_by["number_id"], it.amount_cents] }
  end

  before do
    travel_to(DateTime.new(2025, 1, 1)) do
      create_metric(
        {
          name: "Phone numbers",
          code: "phone_numbers",
          aggregation_type:,
          field_name:,
          recurring: true,
          filters: [{key: "number_type", values: %w[local toll_free]}]
        }
      )

      create_plan(
        {
          name: "Phone numbers",
          code: "phone_numbers",
          interval: "monthly",
          amount_cents: 0,
          amount_currency: "EUR",
          pay_in_advance: false,
          charges: [
            {
              billable_metric_id: organization.billable_metrics.find_by!(code: "phone_numbers").id,
              charge_model: "standard",
              prorated:,
              properties: {amount: "0"},
              filters: [
                {invoice_display_name: "Local", properties: {amount: "1.15", pricing_group_keys:}.compact, values: {number_type: %w[local]}},
                {invoice_display_name: "Toll-free", properties: {amount: "2", pricing_group_keys:}.compact, values: {number_type: %w[toll_free]}}
              ]
            }
          ]
        }
      )

      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_phone_numbers",
          plan_code: "phone_numbers",
          billing_time: "calendar"
        }
      )
    end

    travel_to(DateTime.new(2025, 1, 5)) do
      send_number_event("+33100000001", "local", add_properties)
      send_number_event("+18000000002", "toll_free", add_properties)
      send_number_event("+33100000003", "local", add_properties)
    end

    travel_to(DateTime.new(2025, 2, 1, 1)) { perform_billing }

    travel_to(DateTime.new(2025, 2, 10)) do
      send_number_event("+33100000003", "local", remove_properties)
    end

    travel_to(DateTime.new(2025, 3, 1, 1)) { perform_billing }

    # NOTE: no event is sent in March
    travel_to(DateTime.new(2025, 4, 1, 1)) { perform_billing }
  end

  context "with a recurring sum metric and a compensation event" do
    let(:aggregation_type) { "sum_agg" }
    let(:field_name) { "numbers" }
    let(:add_properties) { {numbers: 1} }
    let(:remove_properties) { {numbers: -1} }

    it "stops billing the removed number from the month it is removed" do
      expect(charge_amounts(Date.new(2025, 2, 1))).to eq("Local" => 2 * 115, "Toll-free" => 200)
      expect(charge_amounts(Date.new(2025, 3, 1))).to eq("Local" => 115, "Toll-free" => 200)
      expect(charge_amounts(Date.new(2025, 4, 1))).to eq("Local" => 115, "Toll-free" => 200)
    end

    context "when the charge is prorated" do
      let(:prorated) { true }

      it "bills the removed number until the day before its removal" do
        # NOTE: January: 2 x 27/31 units at 1.15 and 27/31 unit at 2
        expect(charge_amounts(Date.new(2025, 2, 1))).to eq("Local" => 200, "Toll-free" => 174)
        # NOTE: February: (1 + 9/28) units at 1.15 (the removed number is billed from Feb 1 to Feb 9)
        expect(charge_amounts(Date.new(2025, 3, 1))).to eq("Local" => 152, "Toll-free" => 200)
        expect(charge_amounts(Date.new(2025, 4, 1))).to eq("Local" => 115, "Toll-free" => 200)
      end
    end

    context "with pricing group keys" do
      let(:pricing_group_keys) { %w[number_id] }

      it "bills one fee per number and keeps a zero fee for the removed number" do
        expect(grouped_charge_amounts(Date.new(2025, 2, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Local", "+33100000003", 115],
          ["Toll-free", "+18000000002", 200]
        ])
        # NOTE: the removed number still has events, so its group keeps a zero fee in the next periods
        expect(grouped_charge_amounts(Date.new(2025, 3, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Local", "+33100000003", 0],
          ["Toll-free", "+18000000002", 200]
        ])
        expect(grouped_charge_amounts(Date.new(2025, 4, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Local", "+33100000003", 0],
          ["Toll-free", "+18000000002", 200]
        ])
      end
    end
  end

  context "with a recurring unique count metric and a remove operation" do
    let(:aggregation_type) { "unique_count_agg" }
    let(:field_name) { "number_id" }
    let(:add_properties) { {} }
    let(:remove_properties) { {operation_type: "remove"} }

    it "stops billing the removed number from the month it is removed" do
      expect(charge_amounts(Date.new(2025, 2, 1))).to eq("Local" => 2 * 115, "Toll-free" => 200)
      expect(charge_amounts(Date.new(2025, 3, 1))).to eq("Local" => 115, "Toll-free" => 200)
      expect(charge_amounts(Date.new(2025, 4, 1))).to eq("Local" => 115, "Toll-free" => 200)
    end

    context "when the charge is prorated" do
      let(:prorated) { true }

      it "bills the removed number until the day of its removal" do
        # NOTE: January: 2 x 27/31 units at 1.15 and 27/31 unit at 2
        expect(charge_amounts(Date.new(2025, 2, 1))).to eq("Local" => 200, "Toll-free" => 174)
        # NOTE: February: (1 + 10/28) units at 1.15 (the removed number is billed from Feb 1 to Feb 10)
        expect(charge_amounts(Date.new(2025, 3, 1))).to eq("Local" => 156, "Toll-free" => 200)
        expect(charge_amounts(Date.new(2025, 4, 1))).to eq("Local" => 115, "Toll-free" => 200)
      end
    end

    context "with pricing group keys" do
      let(:pricing_group_keys) { %w[number_id] }

      it "bills one fee per number until the number is removed" do
        expect(grouped_charge_amounts(Date.new(2025, 2, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Local", "+33100000003", 115],
          ["Toll-free", "+18000000002", 200]
        ])
        expect(grouped_charge_amounts(Date.new(2025, 3, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Toll-free", "+18000000002", 200]
        ])
        expect(grouped_charge_amounts(Date.new(2025, 4, 1))).to match_array([
          ["Local", "+33100000001", 115],
          ["Toll-free", "+18000000002", 200]
        ])
      end
    end
  end
end
