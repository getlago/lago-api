# frozen_string_literal: true

require "rails_helper"

describe "Past usage for regrouped advance charges", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly") }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:paid_units) { 10 }

  before do
    create(
      :graduated_charge,
      plan:,
      billable_metric:,
      pay_in_advance: true,
      invoiceable: false,
      regroup_paid_fees: "invoice",
      properties: {
        graduated_ranges: [
          {from_value: 0, to_value: 40, per_unit_amount: "0", flat_amount: "0"},
          {from_value: 41, to_value: nil, per_unit_amount: "0.50", flat_amount: "0"}
        ]
      }
    )
  end

  shared_examples "complete past usage" do
    it "preserves the live unit count after billing without changing invoice amounts" do
      travel_to(Time.zone.local(2024, 6, 1)) do
        create_subscription({external_customer_id: customer.external_id, external_id: external_subscription_id, plan_code: plan.code})
      end

      subscription = customer.subscriptions.sole

      [40, paid_units].reject(&:zero?).each_with_index do |units, index|
        travel_to(Time.zone.local(2024, 6, 15 + index, 12)) do
          create_event({
            code: billable_metric.code,
            external_subscription_id:,
            properties: {billable_metric.field_name => units}
          })
        end
      end

      travel_to(Time.zone.local(2024, 6, 20, 12)) do
        fetch_current_usage(customer:)
        expect(json[:customer_usage][:charges_usage].sole[:units]).to eq((40 + paid_units).to_d.to_s)

        subscription.fees.charge.where("amount_cents > 0").find_each do |fee|
          update_fee(fee.id, {payment_status: "succeeded"})
        end
        expect(subscription.fees.charge.where(amount_cents: 0).sole).to have_attributes(
          units: 40,
          invoice_id: nil,
          payment_status: "pending"
        )
      end

      travel_to(Time.zone.local(2024, 7, 1, 1)) { perform_billing }

      invoice_amounts = customer.invoices.order(:id).pluck(:id, :fees_amount_cents, :total_amount_cents)

      get_with_token(organization, "/api/v1/customers/#{customer.external_id}/past_usage", {external_subscription_id:})

      expect(response).to have_http_status(:success)
      charges_usage = json[:usage_periods].flat_map { |period| period[:charges_usage] }
      expect(charges_usage.sole).to include(
        units: (40 + paid_units).to_d.to_s,
        total_aggregated_units: (40 + paid_units).to_d.to_s,
        amount_cents: paid_units * 50
      )
      expect(customer.invoices.order(:id).pluck(:id, :fees_amount_cents, :total_amount_cents)).to eq(invoice_amounts)
      expect(subscription.fees.charge.where(amount_cents: 0).sole.invoice_id).to be_nil
    end
  end

  include_examples "complete past usage"

  context "when all consumption is free" do
    let(:paid_units) { 0 }

    include_examples "complete past usage"
  end
end
