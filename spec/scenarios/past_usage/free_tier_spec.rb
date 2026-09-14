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

  shared_examples "complete past usage" do |regenerations: 0|
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

      regenerations.times do |index|
        travel_to(Time.zone.local(2024, 7, 2 + index, 12)) do
          invoice = customer.invoices.advance_charges.where(status: :finalized).sole
          void_invoice(invoice)
          regenerated_invoice = Invoices::RegenerateFromVoidedService.call!(
            voided_invoice: invoice,
            fees_params: [{id: invoice.fees.charge.sole.id, subscription_id: subscription.id, units: 10, unit_amount_cents: "0.50"}]
          ).invoice

          get_with_token(organization, "/api/v1/customers/#{customer.external_id}/past_usage", {external_subscription_id:})

          expect(response).to have_http_status(:success)
          periods = json[:usage_periods].index_by { |period| period[:lago_invoice_id] }
          expect(periods.fetch(regenerated_invoice.id)[:charges_usage].sole).to include(units: "50.0", amount_cents: 500)
          expect(periods.fetch(invoice.id)[:charges_usage].sole).to include(units: "10.0", amount_cents: 500)
          expect(regenerated_invoice.fees_amount_cents).to eq(500)
          expect(subscription.fees.charge.where(invoice_id: nil).sole.units).to eq(40)

          get_with_token(organization, "/api/v1/customers/#{customer.external_id}/past_usage",
            {external_subscription_id:, page: 1, per_page: 1})

          expect(response).to have_http_status(:success)
          expect(json[:usage_periods].sole[:lago_invoice_id]).to eq(regenerated_invoice.id)
          expect(json[:usage_periods].sole[:charges_usage].sole).to include(units: "50.0", amount_cents: 500)
        end
      end
    end
  end

  include_examples "complete past usage"

  context "when the invoice is regenerated repeatedly", :with_pdf_generation_stub do
    include_examples "complete past usage", regenerations: 2
  end

  context "when all consumption is free" do
    let(:paid_units) { 0 }

    include_examples "complete past usage"
  end
end
