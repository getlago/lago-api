# frozen_string_literal: true

require 'rails_helper'

describe 'Charge Models - Percentage Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:plan) { create(:plan, organization:, amount_cents: 1000) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type:, field_name:) }

  describe 'with sum_agg' do
    let(:aggregation_type) { 'sum_agg' }
    let(:field_name) { 'amount' }

    describe 'with free_units_per_events and fixed_amount' do
      it 'returns the expected customer usage' do
        travel_to(DateTime.new(2023, 3, 5)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :percentage_charge,
          plan:,
          billable_metric:,
          properties: { rate: '1', fixed_amount: '5', free_units_per_events: 3 },
        )

        travel_to(DateTime.new(2023, 3, 6)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('10.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('20.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('30.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(510)
          expect(json[:customer_usage][:total_amount_cents]).to eq(612)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('40.0')
        end
      end
    end

    describe 'with free_units_per_total_aggregation and fixed_amount' do
      it 'returns the expected customer usage' do
        travel_to(DateTime.new(2023, 3, 5)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :percentage_charge,
          plan:,
          billable_metric:,
          properties: { rate: '1', fixed_amount: '5', free_units_per_total_aggregation: '15.0' },
        )

        travel_to(DateTime.new(2023, 3, 6)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('4.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('8.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('12.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(501)
          expect(json[:customer_usage][:total_amount_cents]).to eq(601)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('16.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(1011)
          expect(json[:customer_usage][:total_amount_cents]).to eq(1213)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('26.0')
        end
      end
    end

    describe 'with free_units_per_events, free_units_per_total_aggregation and fixed_amount (events overage)' do
      it 'returns the expected customer usage' do
        travel_to(DateTime.new(2023, 3, 5)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :percentage_charge,
          plan:,
          billable_metric:,
          properties: {
            rate: '1',
            fixed_amount: '5',
            free_units_per_events: 3,
            free_units_per_total_aggregation: '15.0',
          },
        )

        travel_to(DateTime.new(2023, 3, 6)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('3.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(501)
          expect(json[:customer_usage][:total_amount_cents]).to eq(601)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('4.0')
        end
      end
    end

    describe 'with free_units_per_events, free_units_per_total_aggregation and fixed_amount (total_agg overage)' do
      it 'returns the expected customer usage' do
        travel_to(DateTime.new(2023, 3, 5)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :percentage_charge,
          plan:,
          billable_metric:,
          properties: {
            rate: '1',
            fixed_amount: '5',
            free_units_per_events: 3,
            free_units_per_total_aggregation: '15.0',
          },
        )

        travel_to(DateTime.new(2023, 3, 6)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:total_amount_cents]).to eq(0)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('10.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(505)
          expect(json[:customer_usage][:total_amount_cents]).to eq(606)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('20.0')

          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents]).to eq(1015)
          expect(json[:customer_usage][:total_amount_cents]).to eq(1218)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('30.0')
        end
      end
    end
  end
end
