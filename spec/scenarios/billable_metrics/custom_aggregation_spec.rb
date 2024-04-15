# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Aggregation - Custom Aggregation Scenarios', :scenarios, type: :request, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:billable_metric) { create(:custom_billable_metric, organization:, custom_aggregator:) }

  let(:custom_aggregator) do
    <<~RUBY
      def aggregate(event, previous_state, aggregation_properties)
        previous_units = previous_state[:total_units]
        event_units = BigDecimal(event.properties['value'].to_s)
        storage_zone = event.properties['storage_zone']
        total_units = previous_units + event_units
        ranges = aggregation_properties['ranges']

        result_amount = ranges.each_with_object(0) do |range, amount|
          # Range was already reached
          next amount if range['to'] && previous_units > range['to']

          zone_amount = BigDecimal(range[storage_zone] || '0')

          if !range['to'] || total_units <= range['to']
            # Last matching range is reached
            units_to_use = if previous_units > range['from']
              # All new units are in the current range
              event_units
            else
              # Takes only the new units in the current range
              total_units - range['from']
            end
            break amount += zone_amount * units_to_use

          else
            # Range is not the last one
            units_to_use = if previous_units > range['from']
              # All remaining units in the range
              range['to'] - previous_units
            else
              # All units in the range
              range['to'] - range['from']
            end

            amount += zone_amount * units_to_use
          end

          amount
        end
        { total_units: total_units, amount: result_amount }
      end
    RUBY
  end

  let(:pay_in_advance) { false }

  let(:standard_charge) do
    create(
      :standard_charge,
      billable_metric:,
      plan:,
      pay_in_advance:,
      properties: {
        amount: '2',
        custom_properties: {
          ranges: [
            { from: 0, to: 10, storage_eu: '0', storage_us: '0', storage_asia: '0' },
            { from: 10, to: 20, storage_eu: '0.10', storage_us: '0.20', storage_asia: '0.30' },
            { from: 20, to: nil, storage_eu: '0.20', storage_us: '0.30', storage_asia: '0.40' },
          ],
        },
      },
    )
  end

  let(:custom_charge) do
    create(
      :custom_charge,
      billable_metric:,
      plan:,
      pay_in_advance:,
      properties: {
        custom_properties: {
          ranges: [
            { from: 0, to: 10, storage_eu: '0', storage_us: '0', storage_asia: '0' },
            { from: 10, to: 20, storage_eu: '0.10', storage_us: '0.20', storage_asia: '0.30' },
            { from: 20, to: nil, storage_eu: '0.20', storage_us: '0.30', storage_asia: '0.40' },
          ],
        },
      },
    )
  end

  before do
    standard_charge
    custom_charge
  end

  context 'when in arrears aggregation' do
    it 'create fees for each charges' do
      travel_to(DateTime.new(2024, 2, 1)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      travel_to(DateTime.new(2024, 2, 6, 1)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              value: 1,
              storage_zone: 'storage_eu',
            },
          },
        )

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(200)
        expect(json[:customer_usage][:charges_usage].count).to eq(2)

        standard_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'standard'
        end
        expect(standard_usage[:units]).to eq('1.0')
        expect(standard_usage[:amount_cents]).to eq(200)

        custom_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'custom'
        end
        expect(custom_usage[:units]).to eq('1.0')
        expect(custom_usage[:amount_cents]).to eq(0)
      end

      travel_to(DateTime.new(2024, 2, 6, 2)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              value: 10,
              storage_zone: 'storage_asia',
            },
          },
        )

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(2_230)
        expect(json[:customer_usage][:charges_usage].count).to eq(2)

        standard_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'standard'
        end
        expect(standard_usage[:units]).to eq('11.0')
        expect(standard_usage[:amount_cents]).to eq(2_200)

        custom_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'custom'
        end
        expect(custom_usage[:units]).to eq('11.0')
        expect(custom_usage[:amount_cents]).to eq(30)
      end
    end
  end

  context 'when in advance aggregation' do
    let(:pay_in_advance) { true }

    it 'creates a fee per events' do
      travel_to(DateTime.new(2024, 2, 1)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      travel_to(DateTime.new(2024, 2, 6, 1)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              value: 1,
              storage_zone: 'storage_eu',
            },
          },
        )

        perform_all_enqueued_jobs

        expect(subscription.fees.count).to eq(2)
        expect(CachedAggregation.where(organization_id: organization.id).count).to eq(2)

        standard_fee = subscription.fees.find_by(charge: standard_charge)
        expect(standard_fee.amount_cents).to eq(200)
        expect(standard_fee.events_count).to eq(1)
        expect(standard_fee.units).to eq(1)

        custom_fee = subscription.fees.find_by(charge: custom_charge)
        expect(custom_fee.amount_cents).to eq(0)
        expect(custom_fee.events_count).to eq(1)
        expect(custom_fee.units).to eq(1)
      end

      travel_to(DateTime.new(2024, 2, 6, 2)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              value: 10,
              storage_zone: 'storage_asia',
            },
          },
        )

        expect(subscription.fees.count).to eq(4)
        expect(CachedAggregation.where(organization_id: organization.id).count).to eq(4)

        standard_fee = subscription.fees.order(created_at: :desc).where(charge: standard_charge).first
        expect(standard_fee.amount_cents).to eq(2000)
        expect(standard_fee.events_count).to eq(1)
        expect(standard_fee.units).to eq(10)

        custom_fee = subscription.fees.order(created_at: :desc).where(charge: custom_charge).first
        expect(custom_fee.amount_cents).to eq(30)
        expect(custom_fee.events_count).to eq(1)
        expect(custom_fee.units).to eq(10)
      end

      travel_to(DateTime.new(2024, 2, 6, 3)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              value: 20,
              storage_zone: 'storage_us',
            },
          },
        )

        expect(subscription.fees.count).to eq(6)
        expect(CachedAggregation.where(organization_id: organization.id).count).to eq(6)

        standard_fee = subscription.fees.order(created_at: :desc).where(charge: standard_charge).first
        expect(standard_fee.amount_cents).to eq(4000)
        expect(standard_fee.events_count).to eq(1)
        expect(standard_fee.units).to eq(20)

        custom_fee = subscription.fees.order(created_at: :desc).where(charge: custom_charge).first
        expect(custom_fee.amount_cents).to eq(330)
        expect(custom_fee.events_count).to eq(1)
        expect(custom_fee.units).to eq(20)
      end

      travel_to(DateTime.new(2024, 2, 6, 4)) do
        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(6_560)
        expect(json[:customer_usage][:charges_usage].count).to eq(2)

        standard_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'standard'
        end
        expect(standard_usage[:units]).to eq('31.0')
        expect(standard_usage[:amount_cents]).to eq(6_200)

        custom_usage = json[:customer_usage][:charges_usage].find do |cu|
          cu[:charge][:charge_model] == 'custom'
        end
        expect(custom_usage[:units]).to eq('31.0')
        expect(custom_usage[:amount_cents]).to eq(360)
      end
    end
  end
end
