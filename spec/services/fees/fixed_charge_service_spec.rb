# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::FixedChargeService do
  subject(:fixed_charge_service) do
    described_class.new(invoice:, fixed_charge:, subscription:, boundaries:, context:)
  end

  around { |test| lago_premium!(&test) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:context) { :finalize }
  # let(:apply_taxes) { false }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      status: :active,
      started_at: Time.zone.parse("2022-03-15"),
      customer:
    )
  end

  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: subscription.started_at.to_date.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      timestamp: subscription.started_at.end_of_month.end_of_day + 1.second,
      charges_duration: (
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

        before { event }

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
      end
    end

    # context "with graduated charge model" do
    #   let(:charge) do
    #     create(
    #       :graduated_charge,
    #       plan: subscription.plan,
    #       charge_model: "graduated",
    #       billable_metric:,
    #       properties: {
    #         graduated_ranges: [
    #           {
    #             from_value: 0,
    #             to_value: nil,
    #             per_unit_amount: "0.01",
    #             flat_amount: "0.01"
    #           }
    #         ]
    #       }
    #     )
    #   end

    #   before do
    #     create_list(
    #       :event,
    #       4,
    #       organization: subscription.organization,
    #       subscription:,
    #       code: charge.billable_metric.code,
    #       timestamp: Time.zone.parse("2022-03-16")
    #     )
    #   end

    #   it "creates a fee" do
    #     result = charge_subscription_service.call
    #     expect(result).to be_success
    #     expect(result.fees.first).to have_attributes(
    #       id: String,
    #       invoice_id: invoice.id,
    #       charge_id: charge.id,
    #       amount_cents: 5,
    #       precise_amount_cents: 5.0,
    #       taxes_precise_amount_cents: 0.0,
    #       amount_currency: "EUR",
    #       units: 4.0,
    #       unit_amount_cents: 1,
    #       precise_unit_amount: 0.0125,
    #       events_count: 4
    #     )
    #   end
    # end

    # context "when fee already exists on the period" do
    #   before do
    #     create(:fee, charge:, subscription:, invoice:)
    #   end

    #   it "does not create a new fee" do
    #     expect { charge_subscription_service.call }.not_to change(Fee, :count)
    #   end
    # end

    # context "when billing an new upgraded subscription" do
    #   let(:previous_plan) { create(:plan, amount_cents: subscription.plan.amount_cents - 20) }
    #   let(:previous_subscription) do
    #     create(:subscription, plan: previous_plan, status: :terminated)
    #   end

    #   let(:event) do
    #     create(
    #       :event,
    #       organization: invoice.organization,
    #       subscription:,
    #       code: billable_metric.code,
    #       timestamp: Time.zone.parse("10 Apr 2022 00:01:00")
    #     )
    #   end

    #   let(:boundaries) do
    #     BillingPeriodBoundaries.new(
    #       from_datetime: Time.zone.parse("15 Apr 2022 00:01:00"),
    #       to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
    #       charges_from_datetime: subscription.started_at,
    #       charges_to_datetime: Time.zone.parse("30 Apr 2022 00:01:00"),
    #       charges_duration: 30,
    #       timestamp: Time.zone.parse("2022-05-01T00:01:00")
    #     )
    #   end

    #   before do
    #     subscription.update!(previous_subscription:)
    #     event
    #   end

    #   it "creates a new fee for the complete period" do
    #     result = charge_subscription_service.call
    #     expect(result).to be_success
    #     expect(result.fees.first).to have_attributes(
    #       id: String,
    #       invoice_id: invoice.id,
    #       charge_id: charge.id,
    #       amount_cents: 2000,
    #       precise_amount_cents: 2_000.0,
    #       taxes_precise_amount_cents: 0.0,
    #       amount_currency: "EUR",
    #       units: 1
    #     )
    #   end
    # end

    # context "with all types of aggregation" do
    #   let(:event) do
    #     create(
    #       :event,
    #       code: billable_metric.code,
    #       organization: organization,
    #       external_subscription_id: subscription.external_id,
    #       timestamp: boundaries.charges_to_datetime - 2.days,
    #       properties: {"foo_bar" => 1}
    #     )
    #   end

    #   BillableMetric::AGGREGATION_TYPES.keys.each do |aggregation_type|
    #     before do
    #       billable_metric.update!(
    #         aggregation_type:,
    #         field_name: event.properties.keys.first,
    #         weighted_interval: "seconds",
    #         custom_aggregator: "def aggregate(event, agg, aggregation_properties); { total_units: 1, amount: 1 }; end"
    #       )
    #     end

    #     context "without pricing unit on the charge" do
    #       it "creates fees" do
    #         result = charge_subscription_service.call
    #         expect(result).to be_success
    #         expect(result.fees.first).to have_attributes(
    #           id: String,
    #           invoice_id: invoice.id,
    #           charge_id: charge.id,
    #           amount_cents: 2000,
    #           precise_amount_cents: 2000.0,
    #           taxes_precise_amount_cents: 0.0,
    #           amount_currency: "EUR",
    #           units: 1,
    #           unit_amount_cents: 2000,
    #           precise_unit_amount: 20
    #         )
    #       end

    #       it "does not create pricing unit usage" do
    #         expect { charge_subscription_service.call }.not_to change(PricingUnitUsage, :count)
    #       end
    #     end

    #     context "with pricing unit on the charge" do
    #       before do
    #         create(
    #           :applied_pricing_unit,
    #           organization: subscription.organization,
    #           conversion_rate: 0.25,
    #           pricing_unitable: charge
    #         )
    #       end

    #       it "creates fees" do
    #         result = charge_subscription_service.call
    #         expect(result).to be_success
    #         expect(result.fees.first).to have_attributes(
    #           id: String,
    #           invoice_id: invoice.id,
    #           charge_id: charge.id,
    #           amount_cents: 500,
    #           precise_amount_cents: 500.0,
    #           taxes_precise_amount_cents: 0.0,
    #           amount_currency: "EUR",
    #           units: 1,
    #           unit_amount_cents: 500,
    #           precise_unit_amount: 5
    #         )
    #       end

    #       it "creates pricing unit usage" do
    #         result = charge_subscription_service.call
    #         expect(result).to be_success
    #         expect(result.fees.first.pricing_unit_usage)
    #           .to be_persisted
    #           .and have_attributes(
    #             amount_cents: 2000,
    #             precise_amount_cents: 2000.0,
    #             unit_amount_cents: 2000
    #           )
    #       end
    #     end
    #   end
    # end


    # context "with invoice NOT in draft status" do
    #   before { invoice.finalized! }

    #   it "creates a fee without using adjusted fee attributes" do
    #     result = charge_subscription_service.call

    #     expect(result).to be_success
    #     expect(result.fees.first).to have_attributes(
    #       id: String,
    #       invoice_id: invoice.id,
    #       charge_id: charge.id,
    #       amount_cents: 0,
    #       amount_currency: "EUR",
    #       units: 0,
    #       unit_amount_cents: 0,
    #       precise_unit_amount: 0,
    #       events_count: 0,
    #       payment_status: "pending"
    #     )
    #   end
    # end

    # context "with true-up fee" do
    #   it "creates two fees" do
    #     travel_to(Time.zone.parse("2023-04-01")) do
    #       charge.update!(min_amount_cents: 1000)
    #       result = charge_subscription_service.call

    #       expect(result).to be_success
    #       expect(result.fees.count).to eq(2)
    #       expect(result.fees.pluck(:amount_cents)).to contain_exactly(0, 548) # 548 is 1000 prorated for 17 days.
    #       expect(result.fees.pluck(:precise_amount_cents)).to contain_exactly(0.0, 548.3870967741935) # 548 is 1000 prorated for 17 days.
    #       expect(result.fees.pluck(:taxes_precise_amount_cents)).to contain_exactly(0.0, 0.0) # 548 is 1000 prorated for 17 days.
    #       expect(result.fees.pluck(:unit_amount_cents)).to contain_exactly(0, 548)
    #       expect(result.fees.pluck(:precise_unit_amount)).to contain_exactly(0, 5.483870967741935)
    #     end
    #   end
    # end
  end
end
