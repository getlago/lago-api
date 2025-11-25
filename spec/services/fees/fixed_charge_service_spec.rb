# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::FixedChargeService do
  subject(:fixed_charge_service) do
    described_class.new(invoice:, fixed_charge:, subscription:, boundaries:, context:, apply_taxes:)
  end

  around { |test| lago_premium!(&test) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:context) { :finalize }
  let(:apply_taxes) { false }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      status: :active,
      started_at: Time.zone.parse("2022-03-17"),
      customer:
    )
  end

  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: subscription.started_at.to_date.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      fixed_charges_from_datetime: subscription.started_at.beginning_of_day,
      fixed_charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      timestamp: subscription.started_at.end_of_month.end_of_day + 1.second,
      charges_duration: (
        subscription.started_at.end_of_month.end_of_day - subscription.started_at.beginning_of_month
      ).fdiv(1.day).ceil,
      fixed_charges_duration: (
        subscription.started_at.end_of_month.end_of_day - subscription.started_at.beginning_of_month
      ).fdiv(1.day).ceil
    )
  end

  let(:invoice) do
    create(:invoice, :draft, customer:, organization:)
  end
  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan: subscription.plan,
      charge_model: "standard",
      properties: {
        amount: "20"
      }
    )
  end
  let(:fixed_charge_tax) { create(:fixed_charge_applied_tax, fixed_charge:) }

  describe ".call" do
    context "with standard charge model" do
      it "creates a fee but does not persist it" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee.id).to be_nil
        expect(result.fee.amount_cents).to eq(0)
      end

      context "with preview context and non-persisted subscription" do
        let(:context) { :invoice_preview }
        let(:subscription) do
          Subscription.new(
            organization_id: organization.id,
            customer:,
            plan: create(:plan, organization:),
            subscription_at: Time.current,
            started_at: Time.current,
            billing_time: "calendar"
          )
        end
        let(:fixed_charge) do
          create(
            :fixed_charge,
            plan: subscription.plan,
            charge_model: "standard",
            units: 8,
            properties: {amount: "12.5"}
          )
        end
        let(:invoice) { Invoice.new(customer:, organization:) }

        it "creates fee with default units from fixed_charge" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            invoice: invoice,
            fixed_charge_id: fixed_charge.id,
            units: 8,
            amount_cents: 10000, # $12.5 * 8 units = $100
            precise_amount_cents: 10000.0
          )
        end
      end

      context "with an event" do
        let(:event) do
          create(
            :fixed_charge_event,
            organization: subscription.organization,
            subscription:,
            fixed_charge:,
            timestamp: boundaries.charges_to_datetime - 2.days,
            units: 10
          )
        end

        before do
          event
          fixed_charge_tax
        end

        it "creates a fee" do
          result = fixed_charge_service.call
          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            organization_id: organization.id,
            billing_entity_id: invoice.customer.billing_entity_id,
            invoice_id: invoice.id,
            fixed_charge_id: fixed_charge.id,
            amount_cents: 20000,
            precise_amount_cents: 20000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 10,
            unit_amount_cents: 2000,
            precise_unit_amount: 20,
            events_count: nil,
            payment_status: "pending"
          )
        end

        it "persists fee" do
          expect { fixed_charge_service.call }.to change(Fee, :count)
        end

        context "with preview context" do
          let(:context) { :invoice_preview }

          it "does not persist fee" do
            expect { fixed_charge_service.call }.not_to change(Fee, :count)
          end
        end

        context "with prorated fixed_charge" do
          let(:fixed_charge) do
            create(:fixed_charge, plan: subscription.plan, charge_model: "standard", prorated: true, properties: {amount: "20"})
          end

          it "creates a fee" do
            result = fixed_charge_service.call
            expect(result).to be_success
            prorated_units = (10 * 3.0 / 31).round(6)
            full_units = 10
            expect(result.fee).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              fixed_charge_id: fixed_charge.id,
              amount_cents: 1935,
              precise_amount_cents: 2000 * prorated_units,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: full_units,
              unit_amount_cents: 1935 / full_units,
              precise_unit_amount: 20 * prorated_units / full_units,
              events_count: nil,
              payment_status: "pending"
            )
          end
        end
      end
    end

    context "with graduated charge model " do
      let(:fixed_charge) do
        create(
          :fixed_charge,
          plan: subscription.plan,
          charge_model: "graduated",
          prorated: false,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 5,
                per_unit_amount: "0.1",
                flat_amount: "10"
              },
              {
                from_value: 6,
                to_value: nil,
                per_unit_amount: "2",
                flat_amount: "20"
              }
            ]
          }
        )
      end

      before do
        create(:fixed_charge_event, fixed_charge:, subscription:, timestamp: boundaries.from_datetime + 5.days, units: 31, created_at: boundaries.from_datetime + 5.days)
        create(:fixed_charge_event, fixed_charge:, subscription:, timestamp: boundaries.from_datetime + 10.days, units: 3.1, created_at: boundaries.from_datetime + 10.days)
      end

      # this is not prorated result!
      it "creates a fee" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          fixed_charge_id: fixed_charge.id,
          amount_cents: 1031,
          precise_amount_cents: 1031.0,
          taxes_precise_amount_cents: 0.0,
          amount_currency: "EUR",
          units: 3.1,
          unit_amount_cents: 332,
          precise_unit_amount: (10.31 / 3.1),
          events_count: nil
        )
      end

      context "with prorated fixed_charge" do
        let(:fixed_charge) do
          create(
            :fixed_charge,
            plan: subscription.plan,
            charge_model: "graduated",
            prorated: true,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 5,
                  per_unit_amount: "0.1",
                  flat_amount: "10"
                },
                {
                  from_value: 6,
                  to_value: nil,
                  per_unit_amount: "2",
                  flat_amount: "20"
                }
              ]
            }
          )
        end

        it "creates a fee" do
          result = fixed_charge_service.call
          expect(result).to be_success
          # prorated_units = (31 * 5 / 31.0 + 3.1 * 5 / 31.0)
          # prorated units is 5.5 => total amount is 10_00 + 10 * 5.5 = 1055
          full_units = 3.1
          expect(result.fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            fixed_charge_id: fixed_charge.id,
            amount_cents: (1000 + 10 * 5.5).round,
            precise_amount_cents: 1055.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: full_units,
            unit_amount_cents: (1055 / full_units).round,
            precise_unit_amount: 10.55 / full_units,
            events_count: nil
          )
        end
      end
    end

    context "with volume charge model" do
      let(:fixed_charge) do
        create(:fixed_charge,
          plan: subscription.plan,
          charge_model: "volume",
          prorated: false,
          properties: {
            volume_ranges: [
              {
                from_value: 0,
                to_value: 10,
                per_unit_amount: "0.1",
                flat_amount: "10"
              },
              {
                from_value: 11,
                to_value: nil,
                per_unit_amount: "2",
                flat_amount: "20"
              }
            ]
          })
      end

      before do
        create(:fixed_charge_event, fixed_charge:, subscription:, timestamp: boundaries.from_datetime + 5.days, units: 31, created_at: boundaries.from_datetime + 5.days)
        create(:fixed_charge_event, fixed_charge:, subscription:, timestamp: boundaries.from_datetime + 10.days, units: 3.1, created_at: boundaries.from_datetime + 10.days)
      end

      it "creates a fee" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          fixed_charge_id: fixed_charge.id,
          amount_cents: 1031,
          precise_amount_cents: 1031.0,
          taxes_precise_amount_cents: 0.0,
          amount_currency: "EUR",
          units: 3.1,
          unit_amount_cents: 332,
          precise_unit_amount: 10.31 / 3.1,
          events_count: nil
        )
      end

      context "with prorated fixed_charge" do
        let(:fixed_charge) do
          create(:fixed_charge,
            plan: subscription.plan,
            charge_model: "volume",
            prorated: true,
            properties: {
              volume_ranges: [
                {
                  from_value: 0,
                  to_value: 10,
                  per_unit_amount: "0.1",
                  flat_amount: "10"
                },
                {
                  from_value: 11,
                  to_value: nil,
                  per_unit_amount: "2",
                  flat_amount: "20"
                }
              ]
            })
        end

        it "creates a fee" do
          result = fixed_charge_service.call
          expect(result).to be_success
          # prorated_units = (31 * 5 / 31.0 + 3.1 * 5 / 31.0) = 5.5
          full_units = 3.1
          expect(result.fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            fixed_charge_id: fixed_charge.id,
            amount_cents: 1000 + (10 * 5.5),
            precise_amount_cents: 1055.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: full_units,
            unit_amount_cents: (1055 / full_units).round,
            precise_unit_amount: 10.55 / full_units,
            events_count: nil
          )
        end
      end
    end

    context "when fee already exists on the period" do
      before do
        create(:fee, fixed_charge:, subscription:, invoice:)
      end

      it "does not create a new fee" do
        expect { fixed_charge_service.call }.not_to change(Fee, :count)
      end
    end

    context "when billing a new upgraded subscription" do
      let(:previous_plan) { create(:plan, amount_cents: subscription.plan.amount_cents - 20) }
      let(:previous_subscription) do
        create(:subscription, plan: previous_plan, status: :terminated)
      end

      let(:event) do
        create(
          :fixed_charge_event,
          organization: invoice.organization,
          subscription:,
          fixed_charge:,
          timestamp: Time.zone.parse("10 Apr 2022 00:01:00"),
          units: 10
        )
      end

      let(:boundaries) do
        BillingPeriodBoundaries.new(
          from_datetime: Time.zone.parse("15 Apr 2022 00:01:00"),
          to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
          charges_from_datetime: subscription.started_at,
          charges_to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
          fixed_charges_from_datetime: subscription.started_at,
          fixed_charges_to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
          charges_duration: 30,
          fixed_charges_duration: 30,
          timestamp: Time.zone.parse("2022-05-01T00:01:00")
        )
      end

      before do
        subscription.update!(previous_subscription:)
        event
      end

      it "creates a new fee for the complete period" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          fixed_charge_id: fixed_charge.id,
          amount_cents: 20000,
          precise_amount_cents: 20_000.0,
          taxes_precise_amount_cents: 0.0,
          amount_currency: "EUR",
          units: 10
        )
      end
    end

    context "when applying taxes" do
      let(:apply_taxes) { true }
      let(:event) do
        create(
          :fixed_charge_event,
          organization: subscription.organization,
          subscription:,
          fixed_charge:,
          timestamp: boundaries.charges_to_datetime - 2.days,
          units: 10
        )
      end

      before do
        event
        fixed_charge_tax
      end

      it "creates a fee with taxes" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee).to have_attributes(
          taxes_precise_amount_cents: 20000 * fixed_charge_tax.tax.rate / 100
        )
      end
    end

    context "when fixed charge is pay_in_advance" do
      let(:fixed_charge) do
        create(:fixed_charge, plan: subscription.plan, charge_model: "standard", pay_in_advance: true, properties: {amount: "10"})
      end

      it "creates a fee with pay_in_advance boundaries" do
        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fee.properties).to include(
          "fixed_charges_from_datetime" => Time.parse("2022-04-01T00:00:00.000Z"),
          "fixed_charges_to_datetime" => Time.parse("2022-04-30T23:59:59.999Z"),
          "fixed_charges_duration" => 30
        )
      end
    end

    context "when fixed charge is not pay_in_advance" do
      let(:fixed_charge) do
        create(:fixed_charge, plan: subscription.plan, charge_model: "standard", pay_in_advance: false, properties: {amount: "10"})
      end

      it "creates a fee with current boundaries" do
        result = fixed_charge_service.call
        expect(result).to be_success
        # subscription started at 2022-03-17, so all charges only start from 17th
        expect(result.fee.properties).to include(
          "fixed_charges_from_datetime" => Time.parse("2022-03-17T00:00:00.000Z"),
          "fixed_charges_to_datetime" => Time.parse("2022-03-31T23:59:59.999Z"),
          "fixed_charges_duration" => 31
        )
      end
    end

    context "when there is an adjusted fee for fixed charge" do
      let(:event) do
        create(
          :fixed_charge_event,
          organization:,
          subscription:,
          fixed_charge:,
          timestamp: boundaries.charges_to_datetime - 2.days,
          units: 10
        )
      end

      let(:adjusted_fee) do
        create(
          :adjusted_fee,
          invoice:,
          subscription:,
          fixed_charge:,
          properties:,
          fee_type: :fixed_charge,
          adjusted_units: true,
          adjusted_amount: false,
          units: 5
        )
      end

      let(:properties) do
        {
          fixed_charges_from_datetime: boundaries.fixed_charges_from_datetime,
          fixed_charges_to_datetime: boundaries.fixed_charges_to_datetime
        }
      end

      before do
        event
        adjusted_fee
      end

      context "with adjusted units" do
        it "creates a fee with adjusted units" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            invoice:,
            fixed_charge:,
            amount_cents: 10_000,
            precise_amount_cents: 10_000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 5,
            unit_amount_cents: 2_000,
            precise_unit_amount: 20,
            payment_status: "pending"
          )
        end

        it "updates the adjusted fee with the new fee_id" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(adjusted_fee.reload.fee_id).to eq(result.fee.id)
        end
      end

      context "with adjusted amount" do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            invoice:,
            subscription:,
            fixed_charge:,
            properties:,
            fee_type: :fixed_charge,
            adjusted_units: false,
            adjusted_amount: true,
            units: 10,
            unit_amount_cents: 500,
            unit_precise_amount_cents: 500
          )
        end

        it "creates a fee with adjusted amount" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            invoice:,
            fixed_charge:,
            amount_cents: 5_000,
            precise_amount_cents: 5_000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 10,
            unit_amount_cents: 500,
            precise_unit_amount: 5,
            payment_status: "pending"
          )
        end
      end

      context "with adjusted display name only" do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            invoice:,
            subscription:,
            fixed_charge:,
            properties:,
            fee_type: :fixed_charge,
            adjusted_units: false,
            adjusted_amount: false,
            invoice_display_name: "Custom Fixed Charge Name",
            units: 5
          )
        end

        it "creates a fee with adjusted display name" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            invoice:,
            fixed_charge:,
            amount_cents: 20_000,
            precise_amount_cents: 20_000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 10,
            unit_amount_cents: 2_000,
            precise_unit_amount: 20,
            invoice_display_name: "Custom Fixed Charge Name",
            payment_status: "pending"
          )
        end
      end

      context "with adjusted units set to zero" do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            invoice:,
            subscription:,
            fixed_charge:,
            properties:,
            fee_type: :fixed_charge,
            adjusted_units: true,
            adjusted_amount: false,
            units: 0
          )
        end

        it "creates and persists a fee with zero units" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            invoice:,
            fixed_charge:,
            amount_cents: 0,
            precise_amount_cents: 0.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 0,
            payment_status: "pending"
          )
          # Fee should be persisted despite zero units
          expect(result.fee.persisted?).to be(true)
        end

        it "updates the adjusted fee with the new fee_id" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(adjusted_fee.reload.fee_id).to eq(result.fee.id)
        end
      end

      context "with invoice NOT in draft status" do
        before { invoice.finalized! }

        it "creates a fee without using adjusted fee attributes" do
          result = fixed_charge_service.call

          expect(result).to be_success
          expect(result.fee).to have_attributes(
            id: String,
            invoice:,
            fixed_charge:,
            amount_cents: 20_000,
            precise_amount_cents: 20_000.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: 10,
            unit_amount_cents: 2_000,
            precise_unit_amount: 20,
            payment_status: "pending"
          )
        end
      end
    end
  end
end
