# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::CreateService do
  let(:create_service) { described_class.new(plan:, params:) }

  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }

  describe "#call" do
    subject(:result) { create_service.call }

    context "when plan is not found" do
      let(:plan) { nil }
      let(:params) { {} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "when billable metric is not found" do
      let(:params) { {billable_metric_id: "non-existing-id"} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("billable_metric_not_found")
      end
    end

    context "when plan exists" do
      let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      context "when params are invalid" do
        let(:params) do
          {
            billable_metric_id: sum_billable_metric.id,
            charge_model: "graduated_percentage",
            properties: {
              graduated_percentage_ranges: [
                {
                  from_value: 0,
                  to_value: 10,
                  rate: "3",
                  flat_amount: "0"
                },
                {
                  from_value: 11,
                  to_value: nil,
                  rate: "2",
                  flat_amount: "3"
                }
              ]
            }
          }
        end

        it "returns an error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:charge_model]).to eq(["graduated_percentage_requires_premium_license"])
        end

        it "does not create charge" do
          expect { subject }.not_to change(Charge, :count)
        end
      end

      context "when params are valid" do
        let!(:parent_charge) { create(:standard_charge) }
        let(:pricing_unit) { create(:pricing_unit, organization:) }
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
            applied_pricing_unit: applied_pricing_unit_params,
            billable_metric_id: sum_billable_metric.id,
            charge_model: "standard",
            pay_in_advance: false,
            prorated: true,
            invoiceable: true,
            parent_id: parent_charge.id,
            min_amount_cents: 10,
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
            code: pricing_unit.code,
            conversion_rate: rand(0.1..5.0)
          }
        end

        it "creates new charge" do
          expect { subject }.to change(Charge, :count).by(1)
        end

        it "sets correctly attributes" do
          subject

          created_charge = plan.reload.charges.first
          expect(created_charge).to have_attributes(
            organization_id: organization.id,
            prorated: true,
            pay_in_advance: false,
            parent_id: parent_charge.id,
            properties: {"amount" => "0"}
          )

          created_filter = created_charge.filters.first
          expect(created_filter).to have_attributes(
            invoice_display_name: "Card filter",
            properties: {"amount" => "90"}
          )

          created_filter_value = created_charge.filters.first.values.first
          expect(created_filter_value).to have_attributes(
            billable_metric_filter_id: billable_metric_filter.id,
            values: ["card"]
          )
        end

        context "when premium" do
          around { |test| lago_premium!(&test) }

          it "assigns premium attributes values from params" do
            expect(result.charge)
              .to be_persisted
              .and have_attributes(invoiceable: true, min_amount_cents: 10)
          end

          context "when applied pricing unit params are valid" do
            it "creates applied pricing unit" do
              expect { subject }.to change(AppliedPricingUnit, :count).by(1)
            end
          end

          context "when applied pricing unit params are invalid" do
            let(:applied_pricing_unit_params) do
              {
                code: "non-existing-code",
                conversion_rate: -5
              }
            end

            it "fails with a validation error" do
              expect(result).to be_failure

              expect(result.error.messages).to match(
                conversion_rate: ["value_is_out_of_range"],
                pricing_unit: ["relation_must_exist"]
              )
            end

            it "does not create charge" do
              expect { subject }.not_to change(Charge, :count)
            end

            it "does not create applied pricing unit" do
              expect { subject }.not_to change(AppliedPricingUnit, :count)
            end
          end
        end

        context "when freemium" do
          it "assigns premium attributes default values no matter of values in params" do
            expect(result.charge)
              .to be_persisted
              .and have_attributes(invoiceable: true, min_amount_cents: 0)
          end

          it "does not create applied pricing units" do
            expect { subject }.not_to change(AppliedPricingUnit, :count)
          end
        end
      end
    end
  end
end
