# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateService do
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
          }.merge(pricing_group_keys),
          applied_pricing_unit: applied_pricing_unit_params,
          filters: [
            {
              invoice_display_name: "Card filter",
              properties: {amount: "90"},
              values: {billable_metric_filter.key => ["card"]}
            }
          ]
        }
      end

      let(:applied_pricing_unit_params) do
        {
          conversion_rate: 2.5
        }
      end

      let(:pricing_group_keys) { {} }

      before { create(:applied_pricing_unit, pricing_unitable: charge, conversion_rate: 1.1) }

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
            equal_properties: true,
            equal_applied_pricing_unit_rate: true
          }
        end

        it "updates charge properties and filters" do
          subject

          expect(charge.reload).to have_attributes(properties: {"amount" => "400"})

          expect(charge.filters.first).to have_attributes(
            invoice_display_name: "Card filter",
            properties: {"amount" => "90"}
          )
          expect(charge.filters.first.values.first).to have_attributes(
            billable_metric_filter_id: billable_metric_filter.id,
            values: ["card"]
          )
        end

        it "updates applied pricing unit's conversion rate" do
          expect { subject }.to change(charge.applied_pricing_unit, :conversion_rate).to(2.5)
        end

        context "with pricing_group_keys in the properties" do
          let(:pricing_group_keys) { {pricing_group_keys: ["cloud"]} }

          it "apply the value to the charge" do
            expect { subject }.to change { charge.reload.pricing_group_keys }
              .from(nil).to(["cloud"])
          end
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

          context "with pricing_group_keys in the properties" do
            let(:pricing_group_keys) { {pricing_group_keys: ["cloud"]} }

            it "apply the value to the charge" do
              expect { subject }.to change { charge.reload.pricing_group_keys }
                .from(nil).to(["cloud"])
            end

            context "when charge has a pricing_group_keys" do
              let(:charge) do
                create(
                  :standard_charge,
                  plan:,
                  billable_metric_id: sum_billable_metric.id,
                  amount_currency: "USD",
                  properties: {
                    amount: "300",
                    pricing_group_keys: ["region"]
                  }
                )
              end

              it "overrides the keys" do
                expect { subject }.to change { charge.reload.pricing_group_keys }
                  .from(["region"]).to(["cloud"])
              end
            end
          end

          context "with legacy grouped_by in the properties" do
            let(:pricing_group_keys) { {grouped_by: ["cloud"]} }

            it "apply the value to the charge" do
              expect { subject }.to change { charge.reload.pricing_group_keys }
                .from(nil).to(["cloud"])
            end

            context "when charge has a grouped_by" do
              let(:charge) do
                create(
                  :standard_charge,
                  plan:,
                  billable_metric_id: sum_billable_metric.id,
                  amount_currency: "USD",
                  properties: {
                    amount: "300",
                    grouped_by: ["region"]
                  }
                )
              end

              it "overrides the keys" do
                expect { subject }.to change { charge.reload.pricing_group_keys }
                  .from(["region"]).to(["cloud"])
              end
            end
          end
        end

        context "when applied pricing unit params are invalid" do
          let(:applied_pricing_unit_params) do
            {
              conversion_rate: -1
            }
          end

          it "fails with a validation error" do
            expect(result).to be_failure
            expect(result.error.messages).to match(conversion_rate: ["value_is_out_of_range"])
          end

          it "does not update applied pricing unit's conversion rate" do
            expect { subject }.not_to change { charge.applied_pricing_unit.reload.conversion_rate }
          end
        end
      end
    end
  end
end
