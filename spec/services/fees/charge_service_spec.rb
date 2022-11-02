# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::ChargeService do
  subject(:charge_subscription_service) do
    described_class.new(invoice: invoice, charge: charge, subscription: subscription, boundaries: boundaries)
  end

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: DateTime.parse('2022-03-15'),
    )
  end

  let(:boundaries) do
    {
      from_date: subscription.started_at.to_date,
      to_date: subscription.started_at.end_of_month.to_date,
      charges_from_date: subscription.started_at.to_date,
      charges_to_date: subscription.started_at.end_of_month.to_date,
    }
  end

  let(:invoice) do
    create(:invoice)
  end

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric: billable_metric,
      properties: {
        amount: '20',
        amount_currency: 'EUR',
      },
    )
  end

  describe '.create' do
    context 'without group properties' do
      it 'creates a fee' do
        result = charge_subscription_service.create
        expect(result).to be_success
        created_fee = result.fees.first

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.charge_id).to eq(charge.id)
          expect(created_fee.amount_cents).to eq(0)
          expect(created_fee.amount_currency).to eq('EUR')
          expect(created_fee.vat_amount_cents).to eq(0)
          expect(created_fee.vat_rate).to eq(20.0)
          expect(created_fee.units).to eq(0)
          expect(created_fee.events_count).to eq(0)
        end
      end

      context 'with graduated charge model' do
        let(:charge) do
          create(
            :graduated_charge,
            plan: subscription.plan,
            charge_model: 'graduated',
            billable_metric: billable_metric,
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
            subscription: subscription,
            code: charge.billable_metric.code,
            timestamp: DateTime.parse('2022-03-16'),
          )
        end

        it 'creates a fee' do
          result = charge_subscription_service.create
          expect(result).to be_success
          created_fee = result.fees.first

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.charge_id).to eq(charge.id)
            expect(created_fee.amount_cents).to eq(5)
            expect(created_fee.amount_currency).to eq('EUR')
            expect(created_fee.vat_amount_cents).to eq(1)
            expect(created_fee.vat_rate).to eq(20.0)
            expect(created_fee.units.to_s).to eq('4.0')
          end
        end
      end

      context 'when fee already exists on the period' do
        before do
          create(
            :fee,
            charge: charge,
            subscription: subscription,
            invoice: invoice,
          )
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
            subscription: subscription,
            code: billable_metric.code,
            timestamp: Time.zone.parse('10 Apr 2022 00:01:00'),
          )
        end

        let(:boundaries) do
          {
            from_date: Time.zone.parse('15 Apr 2022 00:01:00').to_date,
            to_date: Time.zone.parse('30 Apr 2022 00:01:00').to_date,
            charges_from_date: subscription.started_at.to_date,
            charges_to_date: Time.zone.parse('30 Apr 2022 00:01:00').to_date,
          }
        end

        before do
          subscription.update!(previous_subscription: previous_subscription)
          event
        end

        it 'creates a new fee for the complete period' do
          result = charge_subscription_service.create
          expect(result).to be_success
          created_fee = result.fees.first

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.charge_id).to eq(charge.id)
            expect(created_fee.amount_cents).to eq(2000)
            expect(created_fee.amount_currency).to eq('EUR')
            expect(created_fee.vat_amount_cents).to eq(400)
            expect(created_fee.vat_rate).to eq(20.0)
            expect(created_fee.units).to eq(1)
          end
        end
      end

      context 'with all types of aggregation' do
        BillableMetric::AGGREGATION_TYPES.each do |aggregation_type|
          before do
            billable_metric.update!(
              aggregation_type: aggregation_type,
              field_name: 'foo_bar',
            )
          end

          it 'creates fees' do
            result = charge_subscription_service.create
            expect(result).to be_success
            created_fee = result.fees.first

            aggregate_failures do
              expect(created_fee.id).not_to be_nil
              expect(created_fee.invoice_id).to eq(invoice.id)
              expect(created_fee.charge_id).to eq(charge.id)
              expect(created_fee.amount_cents).to eq(0)
              expect(created_fee.amount_currency).to eq('EUR')
              expect(created_fee.vat_amount_cents).to eq(0)
              expect(created_fee.vat_rate).to eq(20.0)
              expect(created_fee.units).to eq(0)
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
          billable_metric: billable_metric,
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
            build(
              :group_property,
              group: france,
              values: {
                amount: '40',
                amount_currency: 'EUR',
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
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 4000,
            vat_amount_cents: 800,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            vat_amount_cents: 1000,
            units: 1,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 4000,
            vat_amount_cents: 800,
            units: 1,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 30_000,
            vat_amount_cents: 6000,
            units: 15,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 60_000,
            vat_amount_cents: 12_000,
            units: 12,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 20_000,
            vat_amount_cents: 4000,
            units: 5,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 20_000,
            vat_amount_cents: 4000,
            units: 10,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 60_000,
            vat_amount_cents: 12_000,
            units: 12,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 20_000,
            vat_amount_cents: 4000,
            units: 5,
          )
        end
      end

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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 4000,
            vat_amount_cents: 800,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            vat_amount_cents: 1000,
            units: 1,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 4000,
            vat_amount_cents: 800,
            units: 1,
          )
        end
      end

      it 'creates expected fees for recurring_count_agg aggregation type' do
        boundaries = {
          from_date: subscription.started_at.at_beginning_of_month.next_month.to_date,
          to_date: subscription.started_at.next_month.end_of_month.to_date,
          charges_from_date: subscription.started_at.at_beginning_of_month.next_month.to_date,
          charges_to_date: subscription.started_at.next_month.end_of_month.to_date,
        }

        create(
          :persisted_event,
          customer: subscription.customer,
          billable_metric: billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: 'ext_11',
          added_at: subscription.started_at - 1.day,
          properties: {
            'operation_type' => 'add',
            'unique_id' => 'ext_123',
            'region' => 'usa',
            'foo_bar' => 12,
          },
        )
        create(
          :persisted_event,
          customer: subscription.customer,
          billable_metric: billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: 'ext_12',
          added_at: subscription.started_at - 1.day,
          properties: {
            'operation_type' => 'add',
            'unique_id' => 'ext_456',
            'region' => 'europe',
            'foo_bar' => 10,
          },
        )
        create(
          :persisted_event,
          customer: subscription.customer,
          billable_metric: billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: 'ext_13',
          added_at: subscription.started_at - 1.day,
          properties: {
            'operation_type' => 'add',
            'unique_id' => 'ext_789',
            'country' => 'france',
            'foo_bar' => 5,
          },
        )

        billable_metric.update!(aggregation_type: :recurring_count_agg, field_name: 'foo_bar')
        result = described_class.new(invoice: invoice, charge: charge, subscription: subscription, boundaries: boundaries).create
        expect(result).to be_success
        created_fees = result.fees

        aggregate_failures do
          expect(created_fees.count).to eq(3)
          expect(created_fees).to all(
            have_attributes(
              invoice_id: invoice.id,
              charge_id: charge.id,
              amount_currency: 'EUR',
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 2000,
            vat_amount_cents: 400,
            units: 1,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            vat_amount_cents: 1000,
            units: 1,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 4000,
            vat_amount_cents: 800,
            units: 1,
          )
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
          billable_metric: billable_metric,
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
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 10_000,
            vat_amount_cents: 2000,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 5000,
            vat_amount_cents: 1000,
            units: 1,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 0,
            vat_amount_cents: 0,
            units: 1,
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
          billable_metric: billable_metric,
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
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 5 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 200 + 2 * 2,
            vat_amount_cents: 41,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 1 * 1,
            vat_amount_cents: 1,
            units: 1,
          )
          expect(created_fees.third).to have_attributes(
            group: france,
            amount_cents: 100 + 5 * 1,
            vat_amount_cents: 21,
            units: 1,
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
          billable_metric: billable_metric,
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
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 3,
            vat_amount_cents: 1,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 4,
            vat_amount_cents: 1,
            units: 1,
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
          billable_metric: billable_metric,
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
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'usa', foo_bar: 12 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
          code: charge.billable_metric.code,
          timestamp: DateTime.parse('2022-03-16'),
          properties: { region: 'europe', foo_bar: 10 },
        )
        create(
          :event,
          organization: subscription.organization,
          customer: subscription.customer,
          subscription: subscription,
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
              vat_rate: 20.0,
            ),
          )
          expect(created_fees.first).to have_attributes(
            group: europe,
            amount_cents: 1400,
            vat_amount_cents: 280,
            units: 2,
          )
          expect(created_fees.second).to have_attributes(
            group: usa,
            amount_cents: 1100,
            vat_amount_cents: 220,
            units: 1,
          )
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
      BillableMetric::AGGREGATION_TYPES.each do |aggregation_type|
        before do
          billable_metric.update!(
            aggregation_type: aggregation_type,
            field_name: 'foo_bar',
          )
        end

        it 'initializes fees' do
          result = charge_subscription_service.current_usage

          expect(result).to be_success

          usage_fee = result.fees.first

          aggregate_failures do
            expect(usage_fee.id).to be_nil
            expect(usage_fee.invoice_id).to eq(invoice.id)
            expect(usage_fee.charge_id).to eq(charge.id)
            expect(usage_fee.amount_cents).to eq(0)
            expect(usage_fee.amount_currency).to eq('EUR')
            expect(usage_fee.vat_amount_cents).to eq(0)
            expect(usage_fee.vat_rate).to eq(20.0)
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
          billable_metric: billable_metric,
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
          subscription: subscription,
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
          expect(usage_fee.vat_amount_cents).to eq(1)
          expect(usage_fee.vat_rate).to eq(20.0)
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
