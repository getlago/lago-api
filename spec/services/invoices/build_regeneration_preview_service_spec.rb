# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::BuildRegenerationPreviewService do
  subject(:preview_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan:) }
  let(:invoice) { create(:invoice, organization:, customer:, taxes_rate: 10) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }

  describe "#call" do
    let(:fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: "subscription",
        units: 1,
        amount_cents: 1000,
        taxes_rate: 10,
        amount_currency: "EUR",
        invoice_display_name: "Subscription Fee"
      )
    end

    before do
      allow(Fees::ApplyTaxesService).to receive(:call!).and_call_original
      allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_call_original

      invoice_subscription
      fee
    end

    it "builds a preview invoice with fees" do
      result = preview_service.call

      expect(result).to be_success
      expect(result.invoice.id).to eq(invoice.id)
      expect(result.invoice.fees.size).to eq(1)
      expect(result.invoice.taxes_rate).to eq(0)
    end

    it "calls ApplyTaxesService for fee" do
      preview_service.call

      expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee:)
    end

    it "does not apply provider taxes" do
      preview_service.call

      expect(Invoices::ComputeAmountsFromFees).to have_received(:call).with(
        invoice: be_a(Invoice),
        provider_taxes: nil
      )
    end

    context "when the customer has a tax customer" do
      let(:integration) { create(:anrok_integration, organization:) }

      before do
        create(:anrok_customer, integration:, customer:)
        allow(Invoices::ApplyProviderTaxesService).to receive(:call!)
      end

      it "does not apply provider taxes" do
        preview_service.call

        expect(Invoices::ApplyProviderTaxesService).not_to have_received(:call!)
      end
    end

    context "with multiple fees" do
      let(:charge) { create(:standard_charge, plan:) }
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 3,
          amount_cents: 300,
          taxes_rate: 10,
          amount_currency: "EUR"
        )
      end

      before { charge_fee }

      it "builds a preview invoice with all fees" do
        result = preview_service.call

        expect(result).to be_success
        expect(result.invoice.fees.size).to eq(2)
      end

      it "calls ApplyTaxesService for each fee" do
        preview_service.call

        expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee:)
        expect(Fees::ApplyTaxesService).to have_received(:call!).at_least(:once).with(fee: charge_fee)
      end
    end

    context "when a charge price changed after invoicing" do
      let(:subscription) do
        create(:subscription, customer:, organization:, plan:, started_at: Time.zone.parse("2022-08-01"), subscription_at: Time.zone.parse("2022-08-01"))
      end
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
      let(:parent_plan) { create(:plan, organization:) }
      let(:parent_charge) { create(:standard_charge, plan: parent_plan, organization:, billable_metric:, properties: {amount: "0"}) }
      let(:plan) { create(:plan, organization:, parent: parent_plan) }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          organization:,
          parent: parent_charge,
          billable_metric:,
          prorated: true,
          properties: {amount: current_price}
        )
      end
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          fee_type: "charge",
          units: 1,
          grouped_by:,
          charge_filter:,
          amount_cents: original_amount,
          precise_amount_cents: original_amount,
          unit_amount_cents: original_amount,
          precise_unit_amount: original_amount / 100.to_d,
          taxes_rate: 10,
          amount_currency: "EUR"
        )
      end
      let(:event_timestamp) { Time.zone.parse("2022-08-01") }
      let(:current_price) { "2000" }
      let(:original_amount) { 0 }
      let(:grouped_by) { {} }
      let(:charge_filter) { nil }
      let(:event_properties) { {billable_metric.field_name => "1"} }

      before do
        create(:event, organization:, subscription:, code: billable_metric.code,
          timestamp: event_timestamp, properties: event_properties)
      end

      it "uses the current overridden charge price without persisting or changing the original fee" do
        result = preview_service.call
        preview_fee = result.invoice.fees.sole

        expect(preview_fee).to have_attributes(
          id: fee.id,
          charge_id: charge.id,
          units: 1,
          unit_amount_cents: 200_000,
          precise_unit_amount: 2000,
          amount_cents: 200_000
        )
        expect(preview_fee).not_to be_persisted
        expect(fee.reload).to have_attributes(unit_amount_cents: original_amount, precise_unit_amount: original_amount / 100.to_d, amount_cents: 0)
        expect(invoice.reload.fees).to contain_exactly(fee)
      end

      context "when a terminated subscription receives its first price override", :premium do
        let(:plan) { create(:plan, organization:) }
        let(:charge) do
          create(:standard_charge, plan:, organization:, billable_metric:, prorated: true, properties: {amount: "0"})
        end
        let(:subscription) do
          create(:subscription, customer:, organization:, plan:, status: :terminated,
            started_at: Time.zone.parse("2022-08-01"), subscription_at: Time.zone.parse("2022-08-01"),
            terminated_at: Time.zone.parse("2022-08-31T23:59:59Z"))
        end

        let(:override_params) { {id: charge.id, properties: {amount: "2000"}} }

        before do
          Subscriptions::UpdateService.call!(subscription:, params: {
            plan_overrides: {charges: [override_params]}
          })
        end

        it "uses the subscription override without changing the original fee or charge" do
          preview_fee = preview_service.call.invoice.fees.sole

          expect(subscription.reload.plan.charges.sole.parent_id).to eq(charge.id)
          expect(preview_fee).to have_attributes(units: 1, amount_cents: 200_000)
          expect(fee.reload).to have_attributes(charge_id: charge.id, amount_cents: 0)
          expect(charge.reload.properties).to eq({"amount" => "0"})
        end

        context "with partially prorated usage" do
          let(:event_timestamp) { Time.zone.parse("2022-08-17") }

          it "applies the override price to the original prorated usage" do
            expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(96_776)
          end
        end

        context "when the subscription override is updated again" do
          before do
            override = subscription.reload.plan.charges.sole
            Subscriptions::UpdateService.call!(subscription:, params: {
              plan_overrides: {charges: [{id: override.id, properties: {amount: "3000"}}]}
            })
          end

          it "uses the latest price of the same subscription override" do
            expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(300_000)
          end
        end

        context "when another subscription has its own override" do
          let(:other_subscription) { create(:subscription, customer:, organization:, plan:) }

          before do
            Subscriptions::UpdateService.call!(subscription: other_subscription, params: {
              plan_overrides: {charges: [{id: charge.id, properties: {amount: "5000"}}]}
            })
          end

          it "does not use the other subscription's price" do
            expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(200_000)
          end
        end

        context "with a manual zero price adjustment" do
          before do
            create(:adjusted_fee, organization:, invoice:, fee:, subscription:, charge:, fee_type: :charge,
              adjusted_units: false, adjusted_amount: true, units: 1,
              unit_amount_cents: 0, unit_precise_amount_cents: 0, properties: fee.properties, grouped_by: {})
          end

          it "preserves the explicit zero instead of applying the subscription price" do
            expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(0)
          end
        end

        context "when the override charge is subsequently discarded" do
          let(:original_amount) { 4321 }

          before { Charges::DestroyService.call!(charge: subscription.reload.plan.charges.sole) }

          it "preserves the historical amount instead of using the parent's price" do
            expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(original_amount)
          end
        end

        context "with a cloned charge filter" do
          let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
          let(:charge_filter) do
            filter = create(:charge_filter, charge:, properties: {amount: "0"})
            create(:charge_filter_value, charge_filter: filter, billable_metric_filter: metric_filter, values: ["eu"])
            filter
          end
          let(:event_properties) { {billable_metric.field_name => "1", "region" => "eu"} }
          let(:override_params) do
            {id: charge.id, properties: {amount: "2000"}, filters: [
              {values: {"region" => ["eu"]}, properties: {amount: "100"}}
            ]}
          end

          before do
            create(:event, organization:, subscription:, code: billable_metric.code,
              timestamp: event_timestamp, properties: {billable_metric.field_name => "10", "region" => "us"})
          end

          it "matches the cloned filter while aggregating the original filtered events" do
            preview_fee = preview_service.call.invoice.fees.sole

            expect(preview_fee).to have_attributes(amount_cents: 10_000, charge_filter_id: charge_filter.id)
            expect(charge_filter.reload.properties).to eq({"amount" => "0"})
          end

          context "when the cloned filter is discarded" do
            let(:original_amount) { 4321 }

            before do
              ChargeFilters::DestroyService.call!(charge_filter: subscription.reload.plan.charges.sole.filters.sole)
            end

            it "preserves the historical amount instead of falling back to the base price" do
              expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(original_amount)
            end
          end
        end
      end

      context "with usage beginning partway through the period" do
        let(:event_timestamp) { Time.zone.parse("2022-08-17") }

        it "applies the new price to prorated usage while retaining the displayed units" do
          preview_fee = preview_service.call.invoice.fees.sole

          expect(preview_fee).to have_attributes(units: 1, amount_cents: 96_776, precise_unit_amount: BigDecimal("967.76"))
          expect(fee.reload.amount_cents).to eq(0)
        end

        context "when the price has not changed" do
          let(:current_price) { "100" }
          let(:original_amount) { 4839 }

          it "does not turn the prorated amount into a full-period charge" do
            preview_fee = preview_service.call.invoice.fees.sole

            expect(preview_fee).to have_attributes(units: 1, amount_cents: original_amount)
          end
        end
      end

      context "with a pricing group" do
        let(:grouped_by) { {"region" => "eu"} }
        let(:event_properties) { {billable_metric.field_name => "1", "region" => "eu"} }

        before do
          create(:event, organization:, subscription:, code: billable_metric.code,
            timestamp: event_timestamp, properties: {billable_metric.field_name => "10", "region" => "us"})
        end

        it "reprices only the fee's group" do
          expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(200_000)
        end
      end

      context "with a charge filter" do
        let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
        let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "100"}) }
        let(:event_properties) { {billable_metric.field_name => "1", "region" => "eu"} }

        before do
          create(:charge_filter_value, charge_filter:, billable_metric_filter: metric_filter, values: ["eu"])
          create(:event, organization:, subscription:, code: billable_metric.code,
            timestamp: event_timestamp, properties: {billable_metric.field_name => "10", "region" => "us"})
        end

        it "uses the filter price and only matching events" do
          expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(10_000)
        end

        shared_examples "preserves the historical filtered fee" do
          let(:original_amount) { 4321 }

          it "keeps its historical amount without aggregating unrelated events" do
            preview_fee = preview_service.call.invoice.fees.sole

            expect(preview_fee).to have_attributes(
              units: 1,
              amount_cents: original_amount,
              precise_amount_cents: original_amount,
              unit_amount_cents: original_amount,
              precise_unit_amount: BigDecimal("43.21")
            )
            expect(fee.reload.amount_cents).to eq(original_amount)
            expect(fee.adjusted_fee).to be_nil
          end
        end

        context "when the charge was discarded" do
          before { Charges::DestroyService.call!(charge:) }

          include_examples "preserves the historical filtered fee"
        end

        context "when the selected filter was discarded" do
          before { ChargeFilters::DestroyService.call!(charge_filter:) }

          include_examples "preserves the historical filtered fee"
        end
      end

      context "with a pay-in-advance charge" do
        let(:charge) { create(:standard_charge, plan:, organization:, billable_metric:, prorated: true, pay_in_advance: true, properties: {amount: "2000"}) }

        it "preserves the event-specific historical fee" do
          expect(preview_service.call.invoice.fees.sole.amount_cents).to eq(original_amount)
        end
      end

      context "with an explicit zero price adjustment" do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            organization:,
            invoice:,
            fee:,
            subscription:,
            charge:,
            fee_type: :charge,
            adjusted_units: false,
            adjusted_amount: true,
            units: 1,
            unit_amount_cents: 0,
            unit_precise_amount_cents: 0,
            properties: fee.properties,
            grouped_by: {}
          )
        end

        before { adjusted_fee }

        it "keeps the explicit price adjustment" do
          preview_fee = preview_service.call.invoice.fees.sole

          expect(preview_fee).to have_attributes(
            units: 1,
            unit_amount_cents: 0,
            precise_unit_amount: 0,
            amount_cents: 0
          )
        end

        context "when the original voided invoice charge was soft deleted" do
          let(:invoice) { create(:invoice, organization:, customer:, taxes_rate: 10, status: :voided) }

          before { charge.discard! }

          it "keeps the explicit price adjustment without changing the persisted adjustment" do
            preview_fee = preview_service.call.invoice.fees.sole

            expect(preview_fee).to have_attributes(
              units: 1,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              amount_cents: 0
            )
            expect(fee.reload).to have_attributes(charge_id: charge.id, unit_amount_cents: 0, amount_cents: 0)
            expect(adjusted_fee.reload).to have_attributes(charge: nil, charge_id: charge.id, unit_precise_amount_cents: 0)
          end
        end
      end

      context "with a pricing unit" do
        let(:pricing_unit) { create(:pricing_unit, organization:) }
        let(:historical_pricing_unit_usage) do
          create(
            :pricing_unit_usage,
            organization:,
            fee:,
            pricing_unit:,
            amount_cents: 1,
            precise_amount_cents: 1,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01,
            conversion_rate: 1
          )
        end

        before do
          create(
            :applied_pricing_unit,
            organization:,
            pricing_unit:,
            pricing_unitable: charge,
            conversion_rate: 0.5
          )
          historical_pricing_unit_usage
        end

        it "refreshes the pricing unit usage with the charge amount" do
          preview_fee = preview_service.call.invoice.fees.sole

          expect(preview_fee).to have_attributes(
            unit_amount_cents: 100_000,
            precise_unit_amount: 1000,
            amount_cents: 100_000
          )
          expect(preview_fee.pricing_unit_usage).to have_attributes(
            fee_id: fee.id,
            pricing_unit_id: pricing_unit.id,
            amount_cents: 200_000,
            precise_amount_cents: 200_000,
            unit_amount_cents: 200_000,
            precise_unit_amount: 2000,
            conversion_rate: 0.5
          )
          expect(fee.reload.pricing_unit_usage).to have_attributes(amount_cents: 1, conversion_rate: 1)
        end
      end
    end

    context "when a minimum-charge true-up fee uses a changed charge price" do
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          organization:,
          billable_metric:,
          prorated: true,
          properties: {amount: "2000"}
        )
      end
      let(:true_up_parent_fee) do
        create(:charge_fee, invoice:, subscription:, charge:, units: 1, amount_cents: 0, unit_amount_cents: 0)
      end
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          true_up_parent_fee:,
          units: 1,
          amount_cents: 50_000,
          precise_amount_cents: 50_000,
          unit_amount_cents: 50_000,
          precise_unit_amount: 500
        )
      end

      it "preserves the true-up amount" do
        preview_fee = preview_service.call.invoice.fees.find { |result_fee| result_fee.id == fee.id }

        expect(preview_fee).to have_attributes(
          units: 1,
          unit_amount_cents: 50_000,
          precise_unit_amount: 500,
          amount_cents: 50_000,
          precise_amount_cents: 50_000
        )
      end
    end

    context "with charge models excluded from repricing" do
      let(:recurring_sum_metric) { create(:sum_billable_metric, :recurring, organization:) }
      let(:custom_metric) { create(:custom_billable_metric, organization:) }
      let(:percentage_charge) do
        create(:percentage_charge, plan:, organization:, billable_metric: recurring_sum_metric)
      end
      let(:prorated_graduated_charge) do
        create(:graduated_charge, plan:, organization:, billable_metric: recurring_sum_metric, prorated: true)
      end
      let(:dynamic_charge) do
        create(:dynamic_charge, plan:, organization:, billable_metric: recurring_sum_metric)
      end
      let(:custom_charge) { create(:custom_charge, plan:, organization:, billable_metric: custom_metric) }
      let(:excluded_fees) do
        [
          create(
            :charge_fee,
            invoice:,
            subscription:,
            charge: percentage_charge,
            units: 1,
            amount_cents: 10_100,
            precise_amount_cents: 10_100,
            unit_amount_cents: 10_100,
            precise_unit_amount: 101
          ),
          create(
            :charge_fee,
            invoice:,
            subscription:,
            charge: prorated_graduated_charge,
            units: 1,
            amount_cents: 20_200,
            precise_amount_cents: 20_200,
            unit_amount_cents: 20_200,
            precise_unit_amount: 202
          ),
          create(
            :charge_fee,
            invoice:,
            subscription:,
            charge: dynamic_charge,
            units: 1,
            amount_cents: 30_300,
            precise_amount_cents: 30_300,
            unit_amount_cents: 30_300,
            precise_unit_amount: 303
          ),
          create(
            :charge_fee,
            invoice:,
            subscription:,
            charge: custom_charge,
            units: 1,
            amount_cents: 40_400,
            precise_amount_cents: 40_400,
            unit_amount_cents: 40_400,
            precise_unit_amount: 404
          )
        ]
      end

      before { excluded_fees }

      it "preserves their historical amounts" do
        preview_fees = preview_service.call.invoice.fees.index_by(&:id)

        expect(excluded_fees.map { |original_fee| preview_fees.fetch(original_fee.id).amount_cents }).to eq(
          [10_100, 20_200, 30_300, 40_400]
        )
      end
    end

    context "when a charge price is unchanged" do
      let(:charge) { create(:standard_charge, plan:, properties: {amount: "10"}) }
      let(:fee) do
        create(
          :charge_fee,
          invoice:,
          subscription:,
          charge:,
          units: 2,
          amount_cents: 2000,
          precise_amount_cents: 2000,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          amount_currency: "EUR"
        )
      end

      it "keeps the same charge fee amounts" do
        preview_fee = preview_service.call.invoice.fees.sole

        expect(preview_fee).to have_attributes(
          units: 2,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          amount_cents: 2000
        )
      end
    end

    context "with taxes" do
      let(:tax) { create(:tax, organization:, rate: 12, applied_to_organization: false) }
      let(:applied_tax) { create(:plan_applied_tax, plan:, tax:) }

      before { applied_tax }

      it "applies taxes and assigns ids to applied taxes" do
        result = preview_service.call
        preview_applied_tax = result.invoice.applied_taxes.first

        expect(preview_applied_tax).not_to be_nil
        expect(preview_applied_tax.id).to be_present
        expect(preview_applied_tax.invoice_id).to eq(invoice.id)
        expect(preview_applied_tax.tax_rate).to eq(12)
        expect(result.invoice.taxes_rate).to eq(12)
      end

      it "assigns ids and original fee ids to fee applied taxes" do
        result = preview_service.call
        preview_fee = result.invoice.fees.find { |result_fee| result_fee.id == fee.id }
        preview_fee_applied_tax = preview_fee.applied_taxes.first

        expect(preview_fee_applied_tax).not_to be_nil
        expect(preview_fee_applied_tax.id).to be_present
        expect(preview_fee_applied_tax.fee_id).to eq(fee.id)
        expect(preview_fee_applied_tax.tax_rate).to eq(12)
      end
    end
  end
end
