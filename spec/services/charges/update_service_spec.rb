# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateService, type: :service do
  let(:update_service) { described_class.new(charge:, params:, cascade_options:) }

  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }
  let(:cascade_options) do
    {
      cascade: false
    }
  end

  describe "#call" do
    subject(:result) { update_service.call }

    context "when charge is missing" do
      let(:charge) { nil }
      let(:params) { {} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("charge_not_found")
      end
    end

    context "when charge exists" do
      let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          billable_metric_id: sum_billable_metric.id,
          amount_currency: "USD",
          properties: {
            amount: "300"
          }
        )
      end
      let(:billable_metric_filter) do
        create(
          :billable_metric_filter,
          billable_metric: sum_billable_metric,
          key: "payment_method",
          values: %w[card physical]
        )
      end
      let(:params) do
        {
          id: charge.id,
          billable_metric_id: sum_billable_metric.id,
          charge_model: "standard",
          pay_in_advance: true,
          prorated: true,
          invoiceable: false,
          properties: {
            amount: "400"
          },
          filters: [
            {
              invoice_display_name: "Card filter",
              properties: {amount: "90"},
              values: {billable_metric_filter.key => ["card"]}
            }
          ]
        }
      end

      it "updates existing charge" do
        subject

        expect(charge.reload).to have_attributes(
          prorated: true,
          properties: {"amount" => "400"}
        )

        expect(charge.filters.first).to have_attributes(
          invoice_display_name: "Card filter",
          properties: {"amount" => "90"}
        )
        expect(charge.filters.first.values.first).to have_attributes(
          billable_metric_filter_id: billable_metric_filter.id,
          values: ["card"]
        )
      end

      it "does not update premium attributes" do
        subject

        expect(charge.reload).to have_attributes(pay_in_advance: true, invoiceable: true)
      end

      context "when premium" do
        around { |test| lago_premium!(&test) }

        it "saves premium attributes" do
          subject

          expect(charge.reload).to have_attributes(pay_in_advance: true, invoiceable: false)
        end
      end

      context "when cascade is true" do
        let(:cascade_options) do
          {
            cascade: true,
            parent_filters: [],
            equal_properties: true
          }
        end

        it "updates charge properties and filters" do
          subject

          expect(charge.reload).to have_attributes(
            properties: {"amount" => "400"}
          )

          expect(charge.filters.first).to have_attributes(
            invoice_display_name: "Card filter",
            properties: {"amount" => "90"}
          )
          expect(charge.filters.first.values.first).to have_attributes(
            billable_metric_filter_id: billable_metric_filter.id,
            values: ["card"]
          )
        end

        context "with charge properties already overridden" do
          let(:cascade_options) do
            {
              cascade: true,
              parent_filters: [],
              equal_properties: false
            }
          end

          it "does not update charge properties" do
            expect { subject }.not_to change { charge.reload.properties }
          end
        end
      end
    end
  end
end
