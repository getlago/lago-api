# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ChargeService do
  subject(:charge_subscription_service) do
    described_class.new(invoice:, charge:, subscription:, boundaries:)
  end

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: DateTime.parse('2022-03-15'),
      customer:,
    )
  end

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.to_date.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      timestamp: subscription.started_at.end_of_month.end_of_day + 1.second,
      charges_duration: (
        subscription.started_at.end_of_month.end_of_day - subscription.started_at.beginning_of_month
      ).fdiv(1.day).ceil,
    }
  end

  let(:invoice) do
    create(:invoice, customer:, organization:)
  end

  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric:,
      properties: {
        amount: '20',
      },
    )
  end

  describe '.create' do
    context 'without group properties' do
      it 'creates a fee' do
        result = charge_subscription_service.create
        expect(result).to be_success
        expect(result.fees.first).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          charge_id: charge.id,
          amount_cents: 0,
          amount_currency: 'EUR',
          units: 0,
          unit_amount_cents: 0,
          precise_unit_amount: 0,
          events_count: 0,
          payment_status: 'pending',
        )
      end

      context 'with grouped standard charge' do
        let(:charge) do
          create(
            :standard_charge,
            plan: subscription.plan,
            billable_metric:,
            properties: {
              amount: '20',
              grouped_by: ['cloud'],
            },
          )
        end

        let(:billable_metric) do
          create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'value')
        end

        context 'without events' do
          it 'creates an empty fee' do
            result = charge_subscription_service.create
            expect(result).to be_success
            expect(result.fees.count).to eq(1)

            fee = result.fees.first
            expect(fee).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              amount_currency: 'EUR',
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              grouped_by: { 'cloud' => nil },
            )
          end
        end

        context 'with events' do
          before do
            create(
              :event,
              organization: subscription.organization,
              customer: subscription.customer,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: DateTime.parse('2022-03-16'),
              properties: { cloud: 'aws', value: 10 },
            )

            create(
              :event,
              organization: subscription.organization,
              customer: subscription.customer,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: DateTime.parse('2022-03-16'),
              properties: { cloud: 'aws', value: 5 },
            )

            create(
              :event,
              organization: subscription.organization,
              customer: subscription.customer,
              subscription:,
              code: charge.billable_metric.code,
              timestamp: DateTime.parse('2022-03-16'),
              properties: { cloud: 'gcp', value: 10 },
            )
          end

          it 'creates a fee for each group' do
            result = charge_subscription_service.create
            expect(result).to be_success
            expect(result.fees.count).to eq(2)

            fee1 = result.fees.find { |f| f.grouped_by['cloud'] == 'aws' }
            expect(fee1).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 30_000,
              amount_currency: 'EUR',
              units: 15,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: { 'cloud' => 'aws' },
            )

            fee2 = result.fees.find { |f| f.grouped_by['cloud'] == 'gcp' }
            expect(fee2).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 20_000,
              amount_currency: 'EUR',
              units: 10,
              unit_amount_cents: 2000,
              precise_unit_amount: 20,
              grouped_by: { 'cloud' => 'gcp' },
            )
          end

          context 'with adjusted fee' do
            let(:adjusted_fee) do
              create(
                :adjusted_fee,
                invoice:,
                subscription:,
                charge:,
                properties:,
                fee_type: :charge,
                adjusted_units: true,
                adjusted_amount: false,
                units: 3,
                grouped_by: { 'cloud' => 'aws' },
              )
            end

            let(:properties) do
              {
                charges_from_datetime: boundaries[:charges_from_datetime],
                charges_to_datetime: boundaries[:charges_to_datetime],
              }
            end

            before do
              adjusted_fee
              invoice.draft!
            end

            it 'creates a fee for each group' do
              result = charge_subscription_service.create
              expect(result).to be_success
              expect(result.fees.count).to eq(2)

              fee1 = result.fees.find { |f| f.grouped_by['cloud'] == 'aws' }
              expect(fee1).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 6_000,
                amount_currency: 'EUR',
                units: 3,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: { 'cloud' => 'aws' },
              )

              fee2 = result.fees.find { |f| f.grouped_by['cloud'] == 'gcp' }
              expect(fee2).to have_attributes(
                id: String,
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_cents: 20_000,
                amount_currency: 'EUR',
                units: 10,
                unit_amount_cents: 2000,
                precise_unit_amount: 20,
                grouped_by: { 'cloud' => 'gcp' },
              )
            end
          end

          context 'with recurring weighted sum aggregation' do
            let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

            it 'creates a fee and a quantified event per group' do
              result = charge_subscription_service.create
              expect(result).to be_success

              expect(result.fees.count).to eq(2)
              expect(result.quantified_events.count).to eq(2)
            end
          end
        end
      end

      context 'with graduated charge model' do
        let(:charge) do
          create(
            :graduated_charge,
            plan: subscription.plan,
            charge_model: 'graduated',
            billable_metric:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: nil,
                  per_unit_amount: '0.01',
                  flat_amount: '0.01',
                },
              ],
            },
          )
        end

        before do
          create_list(
            :event,
            4,
            organization: subscription.organization,
            customer: subscription.customer,
            subscription:,
            code: charge.billable_metric.code,
            timestamp: DateTime.parse('2022-03-16'),
          )
        end

        it 'creates a fee' do
          result = charge_subscription_service.create
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 5,
            amount_currency: 'EUR',
            units: 4.0,
            unit_amount_cents: 1,
            precise_unit_amount: 0.0125,
            events_count: 4,
          )
        end
      end

      context 'when fee already exists on the period' do
        before do
          create(:fee, charge:, subscription:, invoice:)
        end

        it 'does not create a new fee' do
          expect { charge_subscription_service.create }.not_to change(Fee, :count)
        end
      end

      context 'when billing an new upgraded subscription' do
        let(:previous_plan) { create(:plan, amount_cents: subscription.plan.amount_cents - 20) }
        let(:previous_subscription) do
          create(:subscription, plan: previous_plan, status: :terminated)
        end

        let(:event) do
          create(
            :event,
            organization: invoice.organization,
            customer: subscription.customer,
            subscription:,
            code: billable_metric.code,
            timestamp: Time.zone.parse('10 Apr 2022 00:01:00'),
          )
        end

        let(:boundaries) do
          {
            from_datetime: Time.zone.parse('15 Apr 2022 00:01:00'),
            to_datetime: Time.zone.parse('30 Apr 2022 00:01:00'),
            charges_from_datetime: subscription.started_at,
            charges_to_datetime: Time.zone.parse('30 Apr 2022 00:01:00'),
            charges_duration: 30,
            timestamp: Time.zone.parse('2022-05-01T00:01:00'),
          }
        end

        before do
          subscription.update!(previous_subscription:)
          event
        end

        it 'creates a new fee for the complete period' do
          result = charge_subscription_service.create
          expect(result).to be_success
          expect(result.fees.first).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            charge_id: charge.id,
            amount_cents: 2000,
            amount_currency: 'EUR',
            units: 1,
          )
        end
      end

      context 'with all types of aggregation' do
        BillableMetric::AGGREGATION_TYPES.keys.each do |aggregation_type|
          before do
            billable_metric.update!(aggregation_type:, field_name: 'foo_bar', weighted_interval: 'seconds')
          end

          it 'creates fees' do
            result = charge_subscription_service.create
            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              amount_currency: 'EUR',
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
            )
          end
        end
      end

      context 'when there is adjusted fee' do
        let(:adjusted_fee) do
          create(
            :adjusted_fee,
            invoice:,
            subscription:,
            charge:,
            properties:,
            fee_type: :charge,
            adjusted_units: true,
            adjusted_amount: false,
            units: 3,
          )
        end
        let(:properties) do
          {
            charges_from_datetime: boundaries[:charges_from_datetime],
            charges_to_datetime: boundaries[:charges_to_datetime],
          }
        end

        before do
          adjusted_fee
          invoice.draft!
        end

        context 'with adjusted units' do
          it 'creates a fee' do
            result = charge_subscription_service.create

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 6_000,
              amount_currency: 'EUR',
              units: 3,
              unit_amount_cents: 2_000,
              precise_unit_amount: 20,
              events_count: 0,
              payment_status: 'pending',
            )
          end

          context 'when there is true-up fee' do
            before { charge.update!(min_amount_cents: 20_000) }

            it 'creates two fees' do
              result = charge_subscription_service.create

              aggregate_failures do
                expect(result).to be_success
                expect(result.fees.count).to eq(2)
                expect(result.fees.pluck(:amount_cents)).to contain_exactly(6_000, 4_967)
                expect(result.fees.pluck(:unit_amount_cents)).to contain_exactly(2_000, 4_967)
                expect(result.fees.pluck(:precise_unit_amount)).to contain_exactly(20, 49.67)
              end
            end
          end

          context 'with standard charge, all types of aggregation and presence of groups' do
            let(:europe) do
              create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
            end

            let(:usa) do
              create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
            end

            let(:france) do
              create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')
            end

            let(:charge) do
              create(
                :standard_charge,
                plan: subscription.plan,
                billable_metric:,
                properties: { amount: '10.12345' },
                group_properties: [
                  build(
                    :group_property,
                    group: europe,
                    values: {
                      amount: '20',
                      amount_currency: 'EUR',
                    },
                  ),
                  build(
                    :group_property,
                    group: usa,
                    values: {
                      amount: '50',
                      amount_currency: 'EUR',
                    },
                  ),
                ],
              )
            end

            let(:adjusted_fee) do
              create(
                :adjusted_fee,
                invoice:,
                subscription:,
                charge:,
                group: usa,
                properties:,
                fee_type: :charge,
                adjusted_units: true,
                adjusted_amount: false,
                units: 3,
              )
            end

            before do
              france

              create(
                :event,
                organization: subscription.organization,
                customer: subscription.customer,
                subscription:,
                code: charge.billable_metric.code,
                timestamp: DateTime.parse('2022-03-16'),
                properties: { region: 'usa', foo_bar: 12 },
              )
              create(
                :event,
                organization: subscription.organization,
                customer: subscription.customer,
                subscription:,
                code: charge.billable_metric.code,
                timestamp: DateTime.parse('2022-03-16'),
                properties: { region: 'europe', foo_bar: 10 },
              )
              create(
                :event,
                organization: subscription.organization,
                customer: subscription.customer,
                subscription:,
                code: charge.billable_metric.code,
                timestamp: DateTime.parse('2022-03-16'),
                properties: { region: 'europe', foo_bar: 5 },
              )
              create(
                :event,
                organization: subscription.organization,
                customer: subscription.customer,
                subscription:,
                code: charge.billable_metric.code,
                timestamp: DateTime.parse('2022-03-16'),
                properties: { country: 'france', foo_bar: 5 },
              )
            end

            it 'creates expected fees for sum_agg aggregation type' do
              billable_metric.update!(aggregation_type: :sum_agg, field_name: 'foo_bar')
              result = charge_subscription_service.create
              expect(result).to be_success
              created_fees = result.fees

              aggregate_failures do
                expect(created_fees.count).to eq(3)
                expect(created_fees).to all(
                  have_attributes(
                    invoice_id: invoice.id,
                    charge_id: charge.id,
                    amount_currency: 'EUR',
                  ),
                )
                expect(created_fees.first).to have_attributes(
                  group: europe,
                  amount_cents: 30_000,
                  units: 15,
                  unit_amount_cents: 2000,
                  precise_unit_amount: 20,
                )

                expect(created_fees.second).to have_attributes(
                  group: usa,
                  amount_cents: 15_000,
                  units: 3,
                  unit_amount_cents: 5000,
                  precise_unit_amount: 50,
                )

                expect(created_fees.third).to have_attributes(
                  group: france,
                  amount_cents: 5062,
                  units: 5,
                  unit_amount_cents: 1012,
                  precise_unit_amount: 10.12345,
                )
              end
            end
          end
        end

        context 'with adjusted amount' do
          let(:adjusted_fee) do
            create(
              :adjusted_fee,
              invoice:,
              subscription:,
              charge:,
              properties:,
              fee_type: :charge,
              adjusted_units: false,
              adjusted_amount: true,
              units: 4,
              unit_amount_cents: 200,
            )
          end

          it 'creates a fee' do
            result = charge_subscription_service.create

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 800,
              amount_currency: 'EUR',
              units: 4,
              unit_amount_cents: 200,
              precise_unit_amount: 2,
              events_count: 0,
              payment_status: 'pending',
            )
          end
        end

        context 'with adjusted display name' do
          let(:adjusted_fee) do
            create(
              :adjusted_fee,
              invoice:,
              subscription:,
              charge:,
              properties:,
              fee_type: :charge,
              adjusted_units: false,
              adjusted_amount: false,
              invoice_display_name: 'test123',
              units: 3,
            )
          end

          it 'creates a fee' do
            result = charge_subscription_service.create

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              amount_currency: 'EUR',
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              events_count: 0,
              payment_status: 'pending',
              invoice_display_name: 'test123',
            )
          end
        end

        context 'with invoice NOT in draft status' do
          before { invoice.finalized! }

          it 'creates a fee without using adjusted fee attributes' do
            result = charge_subscription_service.create

            expect(result).to be_success
            expect(result.fees.first).to have_attributes(
              id: String,
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_cents: 0,
              amount_currency: 'EUR',
              units: 0,
              unit_amount_cents: 0,
              precise_unit_amount: 0,
              events_count: 0,
              payment_status: 'pending',
            )
          end
        end
      end

      context 'with true-up fee' do
        it 'creates two fees' do
          travel_to(DateTime.new(2023, 4, 1)) do
            charge.update!(min_amount_cents: 1000)
            result = charge_subscription_service.create

            aggregate_failures do
              expect(result).to be_success
              expect(result.fees.count).to eq(2)
              expect(result.fees.pluck(:amount_cents)).to contain_exactly(0, 548) # 548 is 1000 prorated for 17 days.
              expect(result.fees.pluck(:unit_amount_cents)).to contain_exactly(0, 548)
              expect(result.fees.pluck(:precise_unit_amount)).to contain_exactly(0, 5.48)
            end
          end
        end
      end
    end

    context 'with standard charge, all types of aggregation and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:france) do
        create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: { amount: '10.12345' },
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                amount: '20',
                amount_currency: 'EUR',
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                amount: '50',
                amount_currency: 'EUR',
              },
            ),
          ],
        )
      end

      before do
        france

        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { country: 'france', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 4000,
            units: 2,
            unit_amount_cents: 2000,
            precise_unit_amount: 20,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            units: 1,
            unit_amount_cents: 5000,
            precise_unit_amount: 50,
          )

          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 1012,
            units: 1,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345,
          )
        end
      end

      it 'creates expected fees for sum_agg aggregation type' do
        billable_metric.update!(aggregation_type: :sum_agg, field_name: 'foo_bar')
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 30_000,
            units: 15,
            unit_amount_cents: 2000,
            precise_unit_amount: 20,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 60_000,
            units: 12,
            unit_amount_cents: 5000,
            precise_unit_amount: 50,
          )

          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 5062,
            units: 5,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345,
          )
        end
      end

      it 'creates expected fees for max_agg aggregation type' do
        billable_metric.update!(aggregation_type: :max_agg, field_name: 'foo_bar')
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 20_000,
            units: 10,
            unit_amount_cents: 2000,
            precise_unit_amount: 20,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 60_000,
            units: 12,
            unit_amount_cents: 5000,
            precise_unit_amount: 50,
          )

          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 5062,
            units: 5,
            unit_amount_cents: 1012,
            precise_unit_amount: 10.12345,
          )
        end
      end

      context 'when unique_count_agg' do
        it 'creates expected fees for unique_count_agg aggregation type' do
          billable_metric.update!(aggregation_type: :unique_count_agg, field_name: 'foo_bar')
          result = charge_subscription_service.create
          expect(result).to be_success
          created_fees = result.fees

          aggregate_failures do
            expect(created_fees.count).to eq(3)
            expect(created_fees).to all(
              have_attributes(
                invoice_id: invoice.id,
                charge_id: charge.id,
                amount_currency: 'EUR',
              ),
            )
            expect(created_fees.first).to have_attributes(
              group: europe,
              amount_cents: 4000,
              units: 2,
            )

            expect(created_fees.second).to have_attributes(
              group: usa,
              amount_cents: 5000,
              units: 1,
            )

            expect(created_fees.third).to have_attributes(
              group: france,
              amount_cents: 1012,
              units: 1,
              unit_amount_cents: 1012,
              precise_unit_amount: 10.12345,
            )
          end
        end
      end
    end

    context 'with package charge and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:france) do
        create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')
      end

      let(:charge) do
        create(
          :package_charge,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                amount: '100',
                free_units: 1,
                package_size: 8,
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                amount: '50',
                free_units: 0,
                package_size: 10,
              },
            ),
            build(
              :group_property,
              group: france,
              values: {
                amount: '40',
                free_units: 1,
                package_size: 5,
              },
            ),
          ],
        )
      end

      before do
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { country: 'france', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            units: 2,
            amount_cents: 10_000,
            unit_amount_cents: 10_000,
            precise_unit_amount: 100,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            units: 1,
            unit_amount_cents: 5000,
            precise_unit_amount: 50,
          )

          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 0,
            units: 1,
            unit_amount_cents: 0,
            precise_unit_amount: 0,
          )
        end
      end
    end

    context 'with percentage charge and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:france) do
        create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')
      end

      let(:charge) do
        create(
          :percentage_charge,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: { rate: '2', fixed_amount: '1' },
            ),
            build(
              :group_property,
              group: usa,
              values: { rate: '1', fixed_amount: '0' },
            ),
            build(
              :group_property,
              group: france,
              values: { rate: '5', fixed_amount: '1' },
            ),
          ],
        )
      end

      before do
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { country: 'france', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 200 + 2 * 2,
            units: 2,
            unit_amount_cents: 102,
            precise_unit_amount: 1.02,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 1 * 1,
            units: 1,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01,
          )

          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 100 + 5 * 1,
            units: 1,
            unit_amount_cents: 105,
            precise_unit_amount: 1.05,
          )
        end
      end
    end

    context 'with graduated charge and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:charge) do
        create(
          :graduated_charge,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                graduated_ranges: [
                  {
                    from_value: 0,
                    to_value: nil,
                    per_unit_amount: '0.01',
                    flat_amount: '0.01',
                  },
                ],
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                graduated_ranges: [
                  {
                    from_value: 0,
                    to_value: nil,
                    per_unit_amount: '0.03',
                    flat_amount: '0.01',
                  },
                ],
              },
            ),
          ],
        )
      end

      before do
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(2)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 3,
            units: 2,
            unit_amount_cents: 1,
            precise_unit_amount: 0.015,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 4,
            units: 1,
            unit_amount_cents: 4,
            precise_unit_amount: 0.04,
          )
        end
      end
    end

    context 'with volume charge and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:charge) do
        create(
          :volume_charge,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                volume_ranges: [
                  { from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '10' },
                ],
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                volume_ranges: [
                  { from_value: 0, to_value: 100, per_unit_amount: '1', flat_amount: '10' },
                ],
              },
            ),
          ],
        )
      end

      before do
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(2)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 1400,
            units: 2,
            unit_amount_cents: 700,
            precise_unit_amount: 7,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 1100,
            units: 1,
            unit_amount_cents: 1100,
            precise_unit_amount: 11,
          )
        end
      end
    end

    context 'with graduated percentage charge and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:charge) do
        create(
          :graduated_percentage_charge,
          plan: subscription.plan,
          billable_metric:,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                graduated_percentage_ranges: [
                  {
                    from_value: 0,
                    to_value: nil,
                    flat_amount: '0.01',
                    rate: '2',
                  },
                ],
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                graduated_percentage_ranges: [
                  {
                    from_value: 0,
                    to_value: nil,
                    flat_amount: '0.01',
                    rate: '3',
                  },
                ],
              },
            ),
          ],
        )
      end

      before do
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
      end

      it 'creates expected fees for count_agg aggregation type' do
        billable_metric.update!(aggregation_type: :count_agg)
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(2)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 5, # 2 × 0.02 + 0.01
            units: 2,
            unit_amount_cents: 2,
            precise_unit_amount: 0.025,
          )

          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 4, # 1 × 0.03 + 0.01
            units: 1,
            unit_amount_cents: 4,
            precise_unit_amount: 0.04,
          )
        end
      end
    end

    context 'with true-up fee and presence of groups' do
      let(:europe) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
      end

      let(:usa) do
        create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          min_amount_cents: 1000,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                amount: '20',
                amount_currency: 'EUR',
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                amount: '50',
                amount_currency: 'EUR',
              },
            ),
          ],
        )
      end

      it 'creates three fees' do
        travel_to(DateTime.new(2023, 4, 1)) do
          result = charge_subscription_service.create

          aggregate_failures do
            expect(result).to be_success
            expect(result.fees.count).to eq(3)
            expect(result.fees.pluck(:amount_cents)).to contain_exactly(0, 0, 548) # 548 is 1000 prorated for 17 days.
          end
        end
      end
    end

    context 'with recurring weighted sum aggregation' do
      let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }

      it 'creates a fee and a quantified event' do
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fee = result.fees.first
        quantified_event = result.quantified_events.first

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.charge_id).to eq(charge.id)
          expect(created_fee.amount_cents).to eq(0)
          expect(created_fee.amount_currency).to eq('EUR')
          expect(created_fee.units).to eq(0)
          expect(created_fee.total_aggregated_units).to eq(0)
          expect(created_fee.events_count).to eq(0)
          expect(created_fee.payment_status).to eq('pending')

          expect(quantified_event.id).not_to be_nil
          expect(quantified_event.organization).to eq(organization)
          expect(quantified_event.external_subscription_id).to eq(subscription.external_id)
          expect(quantified_event.external_id).to be_nil
          expect(quantified_event.group_id).to be_nil
          expect(quantified_event.billable_metric_id).to eq(billable_metric.id)
          expect(quantified_event.added_at).to eq(boundaries[:from_datetime])
          expect(quantified_event.properties[QuantifiedEvent::RECURRING_TOTAL_UNITS]).to eq('0.0')
        end
      end
    end

    context 'with aggregation error' do
      let(:billable_metric) do
        create(
          :billable_metric,
          aggregation_type: 'max_agg',
          field_name: 'foo_bar',
        )
      end
      let(:aggregator_service) { instance_double(BillableMetrics::Aggregations::MaxService) }
      let(:error_result) do
        BaseService::Result.new.service_failure!(code: 'aggregation_failure', message: 'Test message')
      end

      it 'returns an error' do
        allow(BillableMetrics::Aggregations::MaxService).to receive(:new)
          .and_return(aggregator_service)
        allow(aggregator_service).to receive(:aggregate)
          .and_return(error_result)

        result = charge_subscription_service.create

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq('aggregation_failure')
        expect(result.error.error_message).to eq('Test message')

        expect(BillableMetrics::Aggregations::MaxService).to have_received(:new)
        expect(aggregator_service).to have_received(:aggregate)
      end
    end
  end

  describe '.current_usage' do
    context 'with all types of aggregation' do
      BillableMetric::AGGREGATION_TYPES.keys.each do |aggregation_type|
        before do
          billable_metric.update!(aggregation_type:, field_name: 'foo_bar', weighted_interval: 'seconds')

          charge.update!(min_amount_cents: 1000)
        end

        it 'initializes fees' do
          result = charge_subscription_service.current_usage

          expect(result).to be_success

          usage_fee = result.fees.first

          aggregate_failures do
            expect(result.fees.count).to eq(1)
            expect(usage_fee.id).to be_nil
            expect(usage_fee.invoice_id).to eq(invoice.id)
            expect(usage_fee.charge_id).to eq(charge.id)
            expect(usage_fee.amount_cents).to eq(0)
            expect(usage_fee.amount_currency).to eq('EUR')
            expect(usage_fee.units).to eq(0)
          end
        end
      end
    end

    context 'with graduated charge model' do
      let(:charge) do
        create(
          :graduated_charge,
          plan: subscription.plan,
          charge_model: 'graduated',
          billable_metric:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: '0.01',
                flat_amount: '0.01',
              },
            ],
          },
        )
      end

      before do
        create_list(
          :event,
          4,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
        )
      end

      it 'initialize a fee' do
        result = charge_subscription_service.current_usage

        expect(result).to be_success

        usage_fee = result.fees.first

        aggregate_failures do
          expect(usage_fee.id).to be_nil
          expect(usage_fee.invoice_id).to eq(invoice.id)
          expect(usage_fee.charge_id).to eq(charge.id)
          expect(usage_fee.amount_cents).to eq(5)
          expect(usage_fee.amount_currency).to eq('EUR')
          expect(usage_fee.units.to_s).to eq('4.0')
        end
      end
    end

    context 'with aggregation error' do
      let(:billable_metric) do
        create(
          :billable_metric,
          aggregation_type: 'max_agg',
          field_name: 'foo_bar',
        )
      end
      let(:aggregator_service) { instance_double(BillableMetrics::Aggregations::MaxService) }
      let(:error_result) do
        BaseService::Result.new.service_failure!(code: 'aggregation_failure', message: 'Test message')
      end

      it 'returns an error' do
        allow(BillableMetrics::Aggregations::MaxService).to receive(:new)
          .and_return(aggregator_service)
        allow(aggregator_service).to receive(:aggregate)
          .and_return(error_result)

        result = charge_subscription_service.current_usage

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq('aggregation_failure')
        expect(result.error.error_message).to eq('Test message')

        expect(BillableMetrics::Aggregations::MaxService).to have_received(:new)
        expect(aggregator_service).to have_received(:aggregate)
      end
    end
  end
end
