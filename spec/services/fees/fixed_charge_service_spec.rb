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
    create(:invoice, customer:, organization:)
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
            expect(result.fee).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              fixed_charge_id: fixed_charge.id,
              amount_cents: 1935,
              precise_amount_cents: 2000 * prorated_units,
              taxes_precise_amount_cents: 0.0,
              amount_currency: "EUR",
              units: prorated_units,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
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
          prorated_units = (31 * 5 / 31.0 + 3.1 * 5 / 31.0).round(6)
          expect(result.fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            fixed_charge_id: fixed_charge.id,
            amount_cents: 1050 + (2000 + 100),
            precise_amount_cents: 3150.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: prorated_units,
            unit_amount_cents: 572,
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
          prorated_units = (31 * 5 / 31.0 + 3.1 * 5 / 31.0).round(6)
          expect(result.fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            fixed_charge_id: fixed_charge.id,
            amount_cents: 1000 + (10 * 5.5),
            precise_amount_cents: 1055.0,
            taxes_precise_amount_cents: 0.0,
            amount_currency: "EUR",
            units: prorated_units,
            unit_amount_cents: 191,
            precise_unit_amount: 10.55 / 5.5,
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
  end
end
