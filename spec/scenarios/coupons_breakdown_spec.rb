# frozen_string_literal: true

require "rails_helper"

describe "Coupons breakdown Spec", :premium do
  let(:organization) { create(:organization, webhook_url: nil, premium_integrations: ["progressive_billing"]) }

  before do
    organization
    stub_pdf_generation
  end

  context "when there are multiple subscriptions and coupons of different kinds" do
    it "creates an invoice for the expected period" do
      create_metric({name: "Name", code: "bm1", aggregation_type: "sum_agg", field_name: "total1"})
      bm1 = organization.billable_metrics.find_by(code: "bm1")

      create_metric({name: "Name", code: "bm2", aggregation_type: "sum_agg", field_name: "total2"})
      bm2 = organization.billable_metrics.find_by(code: "bm2")

      create_metric({name: "Name", code: "bm3", aggregation_type: "sum_agg", field_name: "total3"})
      bm3 = organization.billable_metrics.find_by(code: "bm3")

      create_metric({name: "Name", code: "bm4", aggregation_type: "sum_agg", field_name: "total4"})
      bm4 = organization.billable_metrics.find_by(code: "bm4")

      create_metric({name: "Name", code: "bm5", aggregation_type: "sum_agg", field_name: "total5"})
      bm5 = organization.billable_metrics.find_by(code: "bm5")

      create_metric({name: "Name", code: "bm6", aggregation_type: "sum_agg", field_name: "total6"})
      bm6 = organization.billable_metrics.find_by(code: "bm6")

      create_metric({name: "Name", code: "bm7", aggregation_type: "sum_agg", field_name: "total7"})
      bm7 = organization.billable_metrics.find_by(code: "bm7")

      create_metric({name: "Name", code: "bm8", aggregation_type: "sum_agg", field_name: "total8"})
      bm8 = organization.billable_metrics.find_by(code: "bm8")

      travel_to(DateTime.new(2023, 1, 1)) do
        create_tax({name: "Banking rates 1", code: "banking_rates1", rate: 10.0})
        create_tax({name: "Banking rates 2", code: "banking_rates2", rate: 20.0})

        create_or_update_customer({external_id: "customer-12345"})

        create_plan(
          {
            name: "P1",
            code: "plan_code",
            interval: "monthly",
            amount_cents: 0,
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm1.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm2.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates2").code]
              },
              {
                billable_metric_id: bm3.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm4.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              }
            ]
          }
        )
        plan = organization.plans.find_by(code: "plan_code")

        create_subscription(
          {
            external_customer_id: "customer-12345",
            external_id: "sub_external_id",
            plan_code: plan.code
          }
        )

        create_plan(
          {
            name: "P2",
            code: "plan_code2",
            interval: "monthly",
            amount_cents: 0,
            amount_currency: "EUR",
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: bm5.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm6.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates2").code]
              },
              {
                billable_metric_id: bm7.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              },
              {
                billable_metric_id: bm8.id,
                charge_model: "standard",
                properties: {amount: "1"},
                tax_codes: [organization.taxes.find_by(code: "banking_rates1").code]
              }
            ]
          }
        )
        plan2 = organization.plans.find_by(code: "plan_code2")

        create_subscription(
          {
            external_customer_id: "customer-12345",
            external_id: "sub_external_id2",
            plan_code: plan2.code
          }
        )

        create_coupon(
          {
            name: "coupon1",
            code: "coupon1_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 2_000,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false,
            applies_to: {
              billable_metric_codes: [bm1.code, bm2.code]
            }
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon1_code"})

        create_coupon(
          {
            name: "coupon2",
            code: "coupon2_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 1_000,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false,
            applies_to: {
              plan_codes: [plan2.code]
            }
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon2_code"})

        create_coupon(
          {
            name: "coupon3",
            code: "coupon3_code",
            coupon_type: "fixed_amount",
            frequency: "once",
            amount_cents: 500,
            amount_currency: "EUR",
            expiration: "time_limit",
            expiration_at: Time.current + 50.days,
            reusable: false
          }
        )
        apply_coupon({external_customer_id: "customer-12345", coupon_code: "coupon3_code"})

        # First subscription events
        create_event(
          {
            code: bm1.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total1: 10}
          }
        )
        create_event(
          {
            code: bm2.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total2: 20}
          }
        )
        create_event(
          {
            code: bm3.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total3: 30}
          }
        )
        create_event(
          {
            code: bm4.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id",
            properties: {total4: 40}
          }
        )

        # Second subscription events
        create_event(
          {
            code: bm5.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total5: 10}
          }
        )
        create_event(
          {
            code: bm6.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total6: 20}
          }
        )
        create_event(
          {
            code: bm7.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total7: 30}
          }
        )
        create_event(
          {
            code: bm8.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: "sub_external_id2",
            properties: {total8: 40}
          }
        )
      end

      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing
      end

      customer = organization.customers.find_by(external_id: "customer-12345")
      invoice = customer.invoices.first
      fees = invoice.fees
      subscription1 = Subscription.find_by(external_id: "sub_external_id")
      subscription2 = Subscription.find_by(external_id: "sub_external_id2")
      sub1_fees = fees.charge.where(subscription: subscription1).joins(:charge)
      sub2_fees = fees.charge.where(subscription: subscription2).joins(:charge)

      # Subscription 1 fees
      expect(sub1_fees.where(charge: {billable_metric_id: bm1.id}).first).to have_attributes(
        amount_cents: 1_000,
        taxes_amount_cents: 32,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 676.47059
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm2.id}).first).to have_attributes(
        amount_cents: 2_000,
        taxes_amount_cents: 129,
        taxes_rate: 20.0,
        precise_coupons_amount_cents: 1352.94117
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm3.id}).first).to have_attributes(
        amount_cents: 3_000,
        taxes_amount_cents: 291,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 88.23529
      )
      expect(sub1_fees.where(charge: {billable_metric_id: bm4.id}).first).to have_attributes(
        amount_cents: 4_000,
        taxes_amount_cents: 388,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 117.64706
      )

      # Subscription 2 fees
      expect(sub2_fees.where(charge: {billable_metric_id: bm5.id}).first).to have_attributes(
        amount_cents: 1_000,
        taxes_amount_cents: 87,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 126.47059
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm6.id}).first).to have_attributes(
        amount_cents: 2_000,
        taxes_amount_cents: 349,
        taxes_rate: 20.0,
        precise_coupons_amount_cents: 252.94118
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm7.id}).first).to have_attributes(
        amount_cents: 3_000,
        taxes_amount_cents: 262,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 379.41176
      )
      expect(sub2_fees.where(charge: {billable_metric_id: bm8.id}).first).to have_attributes(
        amount_cents: 4_000,
        taxes_amount_cents: 349,
        taxes_rate: 10.0,
        precise_coupons_amount_cents: 505.88235
      )

      expect(invoice.fees_amount_cents).to eq(20_000)
      expect(invoice.coupons_amount_cents).to eq(3_500)
      expect(invoice.sub_total_excluding_taxes_amount_cents).to eq(16_500)
      expect(invoice.taxes_amount_cents).to eq(1_889)
      expect(invoice.total_amount_cents).to eq(18_389)
    end
  end

  # BIL-654: matrix inherited from #4057, extended with 50% coupons.
  # Forever fixed coupons keep their existing per-invoice allowance here.
  # Scenarios:
  #   - Sc1: PB $5, final fees $35 (everything in charges or split, doesn't matter — math works the same)
  #   - Sc2: PB $30, final fees $35
  #   - Sc3: PB1 $5 + PB2 $30, final fees $50
  #   - Sc4: PB $40, final fees $0 (no sub, no charges)
  #   - Sc5: PB $40, final fees $20 (no sub, $20 charges)
  #
  # Customer's "paid" = sum of invoice totals; "refund" = sum of credit notes issued.
  # Net cash-out = paid - refund.
  context "with progressive billing and coupons", transaction: false do
    let(:start_time) { DateTime.new(2025, 1, 1) }
    let(:bm) do
      create_metric({name: "U", code: "u", aggregation_type: "sum_agg", field_name: "n"})
      organization.billable_metrics.find_by(code: "u")
    end

    def setup_pb_plan(thresholds_cents)
      create_plan({
        name: "P", code: "pb", interval: "monthly",
        amount_cents: 0, amount_currency: "EUR", pay_in_advance: false,
        charges: [{billable_metric_id: bm.id, charge_model: "standard", pay_in_advance: false, properties: {amount: "1"}}],
        usage_thresholds: thresholds_cents.map { |c| {amount_cents: c} }
      })
      organization.plans.find_by(code: "pb")
    end

    def apply_matrix_coupon(frequency, percentage:, limited_to_metrics:)
      params = {
        name: "C", code: "c", coupon_type: percentage ? "percentage" : "fixed_amount",
        frequency:, frequency_duration: (frequency == "recurring") ? 2 : nil,
        expiration: "no_expiration", reusable: false
      }
      if percentage
        params[:percentage_rate] = 50
      else
        params.merge!(amount_cents: 20_00, amount_currency: "EUR")
      end
      if limited_to_metrics
        params[:applies_to] = {billable_metric_codes: [bm.code]}
      end
      create_coupon(params)
      create_or_update_customer({external_id: "cust"})
      apply_coupon({external_customer_id: "cust", coupon_code: "c"})
    end

    def create_sub(plan)
      travel_to(start_time) { create_subscription({external_customer_id: "cust", external_id: "s", plan_code: plan.code}) }
      Subscription.find_by(external_id: "s")
    end

    def end_of_month_billing
      travel_to(start_time + 1.month) { perform_billing }
    end

    def customer_totals
      customer = organization.customers.find_by(external_id: "cust")
      {
        paid: customer.invoices.sum(:total_amount_cents),
        refund: CreditNote.where(invoice_id: customer.invoices.pluck(:id)).sum(:credit_amount_cents)
      }
    end

    shared_examples "matrix case" do |coupon:, paid:, refund:, percentage: false, limited_to_metrics: false, remaining_uses: nil|
      it "with #{coupon} #{percentage ? "50%" : "$20"} coupon (metric-limited: #{limited_to_metrics}): pays #{paid}, refund #{refund}" do
        plan = setup_pb_plan(thresholds)
        apply_matrix_coupon(coupon, percentage:, limited_to_metrics:)
        sub = create_sub(plan)
        trigger_usage(sub)
        end_of_month_billing

        expect(customer_totals).to eq(paid:, refund:)
        unless remaining_uses.nil?
          customer = organization.customers.find_by(external_id: "cust")
          expect(customer.applied_coupons.sole.frequency_duration_remaining).to eq(remaining_uses)
        end
      end
    end

    context "with Sc1: 1 PB at $5, period total $35" do
      let(:thresholds) { [5_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 5) }
        travel_to(start_time + 15.days) { ingest_event(sub, bm, 30) }
      end

      include_examples "matrix case", coupon: "once", paid: 15_00, refund: 0
      include_examples "matrix case", coupon: "forever", paid: 10_00, refund: 0
      include_examples "matrix case", coupon: "forever", percentage: true, paid: 17_50, refund: 0
      include_examples "matrix case", coupon: "forever", percentage: true, limited_to_metrics: true, paid: 17_50, refund: 0
    end

    context "with Sc2: 1 PB at $30, period total $35" do
      let(:thresholds) { [30_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 30) }
        travel_to(start_time + 15.days) { ingest_event(sub, bm, 5) }
      end

      include_examples "matrix case", coupon: "once", paid: 15_00, refund: 0
      include_examples "matrix case", coupon: "forever", paid: 10_00, refund: 0
      include_examples "matrix case", coupon: "forever", percentage: true, paid: 17_50, refund: 0
      include_examples "matrix case", coupon: "forever", percentage: true, limited_to_metrics: true, paid: 17_50, refund: 0
    end

    context "with Sc3: 2 PBs at $5 and $30, period total $50" do
      let(:thresholds) { [5_00, 30_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 5) }
        travel_to(start_time + 10.days) { ingest_event(sub, bm, 25) }
        travel_to(start_time + 15.days) { ingest_event(sub, bm, 20) }
      end

      include_examples "matrix case", coupon: "once", paid: 30_00, refund: 0
      include_examples "matrix case", coupon: "forever", paid: 5_00, refund: 0
      include_examples "matrix case", coupon: "recurring", percentage: true, paid: 35_00, refund: 0, remaining_uses: 0
      include_examples "matrix case", coupon: "recurring", percentage: true, limited_to_metrics: true, paid: 35_00, refund: 0, remaining_uses: 0
    end

    context "with no new usage after a PB at $40" do
      let(:thresholds) { [40_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 40) }
      end

      include_examples "matrix case", coupon: "recurring", percentage: true, paid: 20_00, refund: 0, remaining_uses: 1
      include_examples "matrix case", coupon: "recurring", percentage: true, limited_to_metrics: true, paid: 20_00, refund: 0, remaining_uses: 1
    end

    context "with Sc4: PB at $40, usage clawed back to $0" do
      let(:thresholds) { [40_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 40) }
        travel_to(start_time + 5.days) { ingest_event(sub, bm, -40) }
        perform_usage_update
      end

      include_examples "matrix case", coupon: "once", paid: 20_00, refund: 20_00
      include_examples "matrix case", coupon: "forever", paid: 20_00, refund: 20_00
    end

    context "with Sc5: PB at $40, usage clawed back to $20" do
      let(:thresholds) { [40_00] }

      def trigger_usage(sub)
        travel_to(start_time + 5.days) { ingest_event(sub, bm, 40) }
        travel_to(start_time + 10.days) { ingest_event(sub, bm, -20) }
      end

      # Known limitation: $10 of coupon stays stranded on the PB for usage that was
      # clawed back. Refund is the proportional cash portion only ($10), not the full
      # $20 needed for the customer to come out at $0 owed.
      include_examples "matrix case", coupon: "once", paid: 20_00, refund: 10_00
      include_examples "matrix case", coupon: "forever", paid: 20_00, refund: 10_00
    end
  end
end
