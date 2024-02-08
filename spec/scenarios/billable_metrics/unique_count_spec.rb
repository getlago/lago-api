# frozen_string_literal: true

require 'rails_helper'

describe 'Aggregation - Unique Count Scenarios', :scenarios, type: :request, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:) }
  let(:charge) do
    create(:standard_charge, plan:, billable_metric:, properties: { amount: '1', grouped_by: %w[key_1 key_2 key_3] })
  end

  before { charge }

  it 'creates fees and keeps the units between periods' do
    travel_to(DateTime.new(2024, 2, 6)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
        },
      )
    end

    subscription = customer.subscriptions.first

    travel_to(DateTime.new(2024, 2, 7)) do
      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          properties: {
            'item_id' => '001',
            'key_1' => '2024',
            'key_2' => 'Feb',
            'key_3' => '08',
          },
        },
      )

      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          properties: {
            'item_id' => '001',
            'key_1' => '2024',
            'key_2' => 'Feb',
            'key_3' => '06',
          },
        },
      )

      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          properties: {
            'item_id' => '002',
            'key_1' => '2024',
            'key_2' => 'Feb',
            'key_3' => '06',
          },
        },
      )

      fetch_current_usage(customer:)
      expect(json[:customer_usage][:total_amount_cents]).to eq(200)
    end
  end

  context 'with in advance charge' do
    let(:charge) do
      create(
        :standard_charge,
        billable_metric:,
        plan:,
        prorated: true,
        pay_in_advance: true,
        properties: {
          amount: '29',
          grouped_by: %w[key_1 key_2 key_3],
        },
      )
    end

    it 'creates fees for each events' do
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

      travel_to(DateTime.new(2024, 2, 1)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => '001',
              'operation_type' => 'remove',
              'key_1' => '2024',
              'key_2' => 'Feb',
              'key_3' => '06',
            },
          },
        )

        expect(Fee.count).to eq(1)

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(0)

        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => '001',
              'operation_type' => 'add',
              'key_1' => '2024',
              'key_2' => 'Feb',
              'key_3' => '06',
            },
          },
        )

        expect(Fee.count).to eq(2)

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(2900)
      end

      travel_to(DateTime.new(2024, 2, 2)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => '001',
              'operation_type' => 'add',
              'key_1' => '2024',
              'key_2' => 'Feb',
              'key_3' => '06',
            },
          },
        )

        expect(Fee.count).to eq(2)

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:total_amount_cents]).to eq(2900)
      end

      travel_to(DateTime.new(2024, 2, 3)) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => '001',
              'operation_type' => 'remove',
              'key_1' => '2024',
              'key_2' => 'Feb',
              'key_3' => '06',
            },
          },
        )

        expect(Fee.count).to eq(3)

        fetch_current_usage(customer:)
        # TODO: change after merge of quantified event handling
        expect(json[:customer_usage][:total_amount_cents]).to eq(0)
      end
    end
  end
end
