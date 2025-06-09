# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::CreateService, type: :service do
  subject(:plans_service) { described_class.new(create_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe "create" do
    subject(:result) { plans_service.call }

    let(:plan_name) { "Some plan name" }
    let(:plan_invoice_display_name) { "Some plan invoice name" }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
    let(:plan_tax) { create(:tax, organization:) }
    let(:charge_tax) { create(:tax, organization:) }
    let(:pricing_unit) { create(:pricing_unit, organization:) }

    let(:billable_metric_filter) do
      create(:billable_metric_filter, billable_metric:, key: "payment_method", values: %w[card physical])
    end

    let(:create_args) do
      {
        name: plan_name,
        invoice_display_name: plan_invoice_display_name,
        organization_id: organization.id,
        code: "new_plan",
        interval: "monthly",
        pay_in_advance: false,
        amount_cents: 200,
        amount_currency: "EUR",
        tax_codes: [plan_tax.code],
        charges: charges_args,
        usage_thresholds: usage_thresholds_args,
        minimum_commitment: minimum_commitment_args
      }
    end

    let(:minimum_commitment_args) do
      {
        amount_cents: minimum_commitment_amount_cents,
        invoice_display_name: minimum_commitment_invoice_display_name,
        tax_codes: [plan_tax.code]
      }
    end

    let(:minimum_commitment_invoice_display_name) { "Minimum spending" }
    let(:minimum_commitment_amount_cents) { 100 }

    let(:charges_args) do
      [
        {
          applied_pricing_unit: applied_pricing_unit_args,
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          min_amount_cents: 100,
          tax_codes: [charge_tax.code],
          filters: [
            {
              values: {billable_metric_filter.key => ["card"]},
              invoice_display_name: "Card filter",
              properties: {amount: "90"}
            }
          ]
        },
        {
          applied_pricing_unit: applied_pricing_unit_args,
          billable_metric_id: sum_billable_metric.id,
          charge_model: "graduated",
          pay_in_advance: true,
          invoiceable: false,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 10,
                per_unit_amount: "2",
                flat_amount: "0"
              },
              {
                from_value: 11,
                to_value: nil,
                per_unit_amount: "3",
                flat_amount: "3"
              }
            ]
          }
        }
      ]
    end

    let(:applied_pricing_unit_args) do
      {
        code: pricing_unit.code,
        conversion_rate: rand(0.1..5.0)
      }
    end

    let(:usage_thresholds_args) do
      [
        {
          threshold_display_name: "Threshold 1",
          amount_cents: 1_000
        },
        {
          threshold_display_name: "Threshold 2",
          amount_cents: 10_000
        },
        {
          threshold_display_name: "Threshold 3",
          amount_cents: 100,
          recurring: true
        }
      ]
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Utils::ActivityLog).to receive(:produce)
    end

    it "creates a plan" do
      expect { plans_service.call }
        .to change(Plan, :count).by(1)

      plan = Plan.order(:created_at).last
      expect(plan.taxes.pluck(:code)).to eq([plan_tax.code])
      expect(plan.invoice_display_name).to eq(plan_invoice_display_name)
    end

    it "does not create minimum commitment" do
      plans_service.call

      plan = Plan.order(:created_at).last

      expect(plan.minimum_commitment).to be_nil
    end

    context "without premium license" do
      it "does not create progressive billing thresholds" do
        plans_service.call

        plan = Plan.order(:created_at).last

        expect(plan.usage_thresholds.count).to eq(0)
      end

      it "does not create applied pricing units" do
        expect { result }.not_to change(AppliedPricingUnit, :count)
      end
    end

    context "with premium license" do
      around { |test| lago_premium!(&test) }

      context "when progressive billing premium integration is not present" do
        it "does not create progressive billing thresholds" do
          plans_service.call

          plan = Plan.order(:created_at).last

          expect(plan.usage_thresholds.count).to eq(0)
        end
      end

      context "when progressive billing premium integration is present" do
        before do
          organization.update!(premium_integrations: ["progressive_billing"])
        end

        it "creates progressive billing thresholds" do
          plans_service.call

          plan = Plan.order(:created_at).last
          usage_thresholds = plan.usage_thresholds.order(threshold_display_name: :asc)

          expect(plan.usage_thresholds.count).to eq(3)
          expect(usage_thresholds.first).to have_attributes(amount_cents: 1_000)
          expect(usage_thresholds.second).to have_attributes(amount_cents: 10_000)
          expect(usage_thresholds.third).to have_attributes(amount_cents: 100)
        end
      end

      context "when applied pricing params provided" do
        context "when params are valid" do
          it "creates applied pricing units" do
            expect { result }.to change(AppliedPricingUnit, :count).by(2)
          end
        end

        context "when params are invalid" do
          let(:applied_pricing_unit_args) do
            {code: "non-existing-code"}
          end

          it "fails with a validation error" do
            expect(result).to be_failure
            expect(result.error).to be_a(BaseService::ValidationFailure)

            expect(result.error.messages).to match(
              conversion_rate: ["value_is_mandatory", "is not a number"],
              pricing_unit: ["relation_must_exist"]
            )
          end

          it "does not create applied pricing unit" do
            expect { result }.not_to change(AppliedPricingUnit, :count)
          end

          it "does not create plan" do
            expect { result }.not_to change(Plan, :count)
          end
        end
      end
    end

    it "creates charges" do
      plans_service.call

      plan = Plan.order(:created_at).last
      expect(plan.charges.count).to eq(2)

      standard_charge = plan.charges.standard.first
      graduated_charge = plan.charges.graduated.first

      expect(standard_charge).to have_attributes(
        organization_id: organization.id,
        pay_in_advance: false,
        prorated: false,
        min_amount_cents: 0,
        invoiceable: true,
        properties: {"amount" => "0"}
      )
      expect(standard_charge.taxes.pluck(:code)).to eq([charge_tax.code])
      expect(standard_charge.filters.first).to have_attributes(
        invoice_display_name: "Card filter",
        properties: {"amount" => "90"}
      )
      expect(standard_charge.filters.first.values.first).to have_attributes(
        billable_metric_filter_id: billable_metric_filter.id,
        values: ["card"]
      )

      expect(graduated_charge).to have_attributes(
        organization_id: organization.id,
        pay_in_advance: true,
        invoiceable: true,
        prorated: false
      )
    end

    it "calls SegmentTrackJob" do
      plan = plans_service.call.plan

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "plan_created",
        properties: {
          code: plan.code,
          name: plan.name,
          invoice_display_name: plan.invoice_display_name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: "arrears",
          trial: plan.trial_period,
          nb_charges: 2,
          nb_standard_charges: 1,
          nb_percentage_charges: 0,
          nb_graduated_charges: 1,
          nb_package_charges: 0,
          organization_id: plan.organization_id,
          parent_id: nil
        }
      )
    end

    it "produces an activity log" do
      result = described_class.call(create_args)

      expect(Utils::ActivityLog).to have_received(:produce).with(result.plan, "plan.created")
    end

    context "when premium" do
      around { |test| lago_premium!(&test) }

      let(:charges_args) do
        [
          {
            billable_metric_id: billable_metric.id,
            charge_model: "standard",
            min_amount_cents: 100,
            tax_codes: [charge_tax.code]
          },
          {
            billable_metric_id: sum_billable_metric.id,
            charge_model: "graduated_percentage",
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: "invoice",
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
        ]
      end

      it "saves premium attributes" do
        plan = plans_service.call.plan

        expect(plan.minimum_commitment).to have_attributes(
          {
            amount_cents: minimum_commitment_amount_cents,
            invoice_display_name: minimum_commitment_invoice_display_name
          }
        )

        expect(plan.charges.standard.first).to have_attributes(
          {
            organization_id: organization.id,
            pay_in_advance: false,
            min_amount_cents: 100,
            invoiceable: true
          }
        )

        expect(plan.charges.graduated_percentage.first).to have_attributes(
          {
            organization_id: organization.id,
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: "invoice",
            charge_model: "graduated_percentage"
          }
        )
      end
    end

    context "with code already used by a deleted plan" do
      it "creates a plan with the same code" do
        create(:plan, organization:, code: "new_plan", deleted_at: Time.current)

        expect { plans_service.call }.to change(Plan, :count).by(1)

        plans = organization.plans.with_discarded
        expect(plans.count).to eq(2)
        expect(plans.pluck(:code).uniq).to eq(["new_plan"])
      end
    end

    context "with validation error" do
      let(:plan_name) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
      end

      context "with premium charge model" do
        let(:plan_name) { "foo" }
        let(:charges_args) do
          [
            {
              billable_metric_id: sum_billable_metric.id,
              charge_model: "graduated_percentage",
              pay_in_advance: true,
              invoiceable: false,
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
          ]
        end

        it "returns an error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:charge_model]).to eq(["graduated_percentage_requires_premium_license"])
        end
      end
    end

    context "with metrics from other organization" do
      let(:billable_metric) { create(:billable_metric) }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("billable_metrics_not_found")
      end
    end
  end
end
