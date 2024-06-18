# frozen_string_literal: true

require 'rails_helper'

describe 'Recurring Non Invoiceable Fees', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: 'http://fees.test/wh') }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:, code: 'seats') }
  let(:plan) { create(:plan, organization:, amount_cents: 49.99, pay_in_advance: true) }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:charge) do
    create(:charge, {
      plan:,
      billable_metric:,
      invoiceable:,
      pay_in_advance:,
      prorated: true,
      properties: {amount: '30', grouped_by:}
    })
  end
  let(:subscription) { customer.subscriptions.first }

  def send_event!(item_id)
    create_event(
      {
        code: billable_metric.code,
        transaction_id: "tr_#{SecureRandom.hex(16)}",
        external_subscription_id:,
        properties: {'item_id' => item_id}
      }
    )
  end

  before do
    charge
    WebMock.stub_request(:post, 'http://fees.test/wh').to_return(status: 200, body: '', headers: {})
  end

  context 'when charge is pay in advance' do
    let(:pay_in_advance) { true }

    context 'with invoiceable = false' do
      let(:invoiceable) { false }

      # rubocop:disable RSpec/ExpectInHook
      before do
        travel_to(Time.zone.parse('2024-06-05T12:12:00')) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
          expect(customer.invoices.count).to eq(1)
        end

        (1..5).each do |i|
          travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
            send_event! "user_#{i}"
            expect(subscription.fees.charge.count).to eq(i)
            expect(subscription.fees.charge.order(created_at: :desc).first.amount_cents).to eq((21 - i) * 100)
          end
        end
      end
      # rubocop:enable RSpec/ExpectInHook

      context 'without grouped_by' do
        let(:grouped_by) { nil }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 2

            recurring_fee = Fee.where(subscription:, charge:, created_at: Time.current.to_date..).sole
            expect(recurring_fee.units).to eq 5
            expect(recurring_fee.invoice_id).to be_nil
            expect(recurring_fee.amount_cents).to eq(30 * 5 * 100)
          end

          travel_to(Time.zone.parse('2024-07-12T01:10:00')) do
            send_event! "user_july_1"
            send_event! "user_july_2"
          end

          travel_to(Time.zone.parse('2024-08-01T01:10:00')) do # August BILLING DAY !
            expect(Fee.where(subscription:, charge:, created_at: Time.current.to_date..).count).to eq 0

            perform_billing

            expect(subscription.invoices.count).to eq 3

            expect(a_request(:post, "http://fees.test/wh").with(
              body: hash_including(webhook_type: 'fee.created', fee: hash_including({
                'units' => '7.0',
                'from_date' => "2024-07-01T00:00:00+00:00",
                'to_date' => "2024-07-31T23:59:59+00:00",
              }))
            )).to have_been_made.once

            recurring_fee = Fee.where(subscription:, charge:, created_at: Time.current.to_date..).sole
            expect(recurring_fee.units).to eq 7
            expect(recurring_fee.invoice_id).to be_nil
            expect(recurring_fee.amount_cents).to eq(30 * 7 * 100)
          end
        end
      end

      context 'with grouped_by on unique field_name' do
        let(:grouped_by) { ['item_id'] }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # July BILLING DAY !
            expect(Fee.where(subscription:, charge:, created_at: Time.current.to_date..).count).to eq 0

            perform_billing
            expect(subscription.invoices.count).to eq 2

            recurring_fees = Fee.where(subscription:, charge:, created_at: Time.current.to_date..)
            expect(recurring_fees.count).to eq 5
            expect(recurring_fees).to all(have_attributes(units: 1, invoice_id: nil, amount_cents: 30 * 100))
          end

          travel_to(Time.zone.parse('2024-07-12T01:10:00')) do
            send_event! "user_july_1"
            send_event! "user_july_2"
          end

          travel_to(Time.zone.parse('2024-08-01T01:10:00')) do # August BILLING DAY !
            expect(Fee.where(subscription:, charge:, created_at: Time.current.to_date..).count).to eq 0

            perform_billing
            expect(subscription.invoices.count).to eq 3

            expect(a_request(:post, "http://fees.test/wh").with(
              body: hash_including(webhook_type: 'fee.created', fee: hash_including({
                'lago_invoice_id' => nil,
                'units' => '1.0',
                'from_date' => "2024-07-01T00:00:00+00:00",
                'to_date' => "2024-07-31T23:59:59+00:00",
              }))
            )).to have_been_made.times(7)

            recurring_fees = Fee.where(subscription:, charge:, created_at: Time.current.to_date..)
            expect(recurring_fees.count).to eq 7
            expect(recurring_fees).to all(have_attributes(units: 1, invoice_id: nil, amount_cents: 30 * 100))
          end
        end
      end
    end

    context 'with invoiceable = true' do
      let(:invoiceable) { true }

      # rubocop:disable RSpec/ExpectInHook
      before do
        travel_to(Time.zone.parse('2024-06-05T12:12:00')) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
          expect(customer.invoices.count).to eq(1)
        end

        (1..5).each do |i|
          travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
            send_event! "user_#{i}"
            expect(subscription.invoices.count).to eq(i + 1)
            expect(subscription.invoices.order(created_at: :desc).first.fees.sole.amount_cents).to eq((21 - i) * 100)
          end
        end
      end
      # rubocop:enable RSpec/ExpectInHook

      context 'without grouped_by' do
        let(:grouped_by) { nil }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 7

            renewal_invoice = subscription.invoices.order(created_at: :desc).first
            recurring_fee = renewal_invoice.fees.charge.sole
            expect(recurring_fee.units).to eq 5
            expect(recurring_fee.amount_cents).to eq(30 * 5 * 100)
          end
        end
      end

      context 'with grouped_by on unique field_name' do
        let(:grouped_by) { ['item_id'] }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 7

            recurring_fees = Fee.where(subscription:, charge:, created_at: Time.current.to_date..)
            expect(recurring_fees.count).to eq 5

            renewal_invoice = subscription.invoices.order(created_at: :desc).first
            recurring_fees = renewal_invoice.fees.charge
            expect(recurring_fees.count).to eq 5
            expect(recurring_fees).to all(have_attributes(units: 1, amount_cents: 30 * 100))
          end
        end
      end
    end
  end

  context 'when charge is pay in arrears' do
    let(:pay_in_advance) { false }

    context 'with invoiceable = false' do
      let(:invoiceable) { false }

      # rubocop:disable RSpec/ExpectInHook
      before do
        travel_to(Time.zone.parse('2024-06-05T12:12:00')) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
          expect(customer.invoices.count).to eq(1)
        end

        (1..5).each do |i|
          travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
            send_event! "user_#{i}"
          end
        end
        expect(Fee.charge.count).to eq 0
      end
      # rubocop:enable RSpec/ExpectInHook

      context 'without grouped_by' do
        let(:grouped_by) { nil }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 2

            expect(Fee.where(subscription:, charge:, created_at: Time.current.to_date..).count).to eq(0)
            # NOTE: This is should what happen if the feature was supported ⤵️
            # recurring_fee = Fee.where(subscription:, charge:, created_at: Time.current.to_date..).sole
            # expect(recurring_fee.units).to eq 5
            # expect(recurring_fee.invoice_id).to be_nil
            # expect(recurring_fee.amount_cents).to eq((20 + 19 + 18 + 17 + 16) * 100)
          end
        end
      end

      context 'with grouped_by on unique field_name' do
        let(:grouped_by) { ['item_id'] }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 2

            expect(Fee.where(subscription:, charge:, created_at: Time.current.to_date..).count).to eq 0
            # NOTE: This is should what happen if the feature was supported ⤵️
            # recurring_fees = Fee.where(subscription:, charge:, created_at: Time.current.to_date..)
            # expect(recurring_fees.count).to eq 5
            # expect(recurring_fees).to all(have_attributes(units: 1, invoice_id: nil))
            # expect(recurring_fees.map(&:amount_cents).sort).to eq([20, 19, 18, 17, 16].sort.map { |i| i * 100 })
          end
        end
      end
    end

    context 'with invoiceable = true' do
      let(:invoiceable) { true }

      # rubocop:disable RSpec/ExpectInHook
      before do
        travel_to(Time.zone.parse('2024-06-05T12:12:00')) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
          expect(customer.invoices.count).to eq(1)
        end

        (1..5).each do |i|
          travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
            send_event! "user_#{i}"
          end
        end
        expect(subscription.invoices.count).to eq 1
      end
      # rubocop:enable RSpec/ExpectInHook

      context 'without grouped_by' do
        let(:grouped_by) { nil }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 2

            renewal_invoice = subscription.invoices.order(created_at: :desc).first
            recurring_fee = renewal_invoice.fees.charge.sole
            expect(recurring_fee.units).to eq 5
            expect(recurring_fee.amount_cents).to eq((20 + 19 + 18 + 17 + 16) * 100)
          end
        end
      end

      context 'with grouped_by on unique field_name' do
        let(:grouped_by) { ['item_id'] }

        it 'creates one fee for all events' do
          travel_to(Time.zone.parse('2024-07-01T00:10:00')) do # BILLING DAY !
            perform_billing

            expect(subscription.invoices.count).to eq 2

            recurring_fees = Fee.where(subscription:, charge:, created_at: Time.current.to_date..)
            expect(recurring_fees.count).to eq 5

            renewal_invoice = subscription.invoices.order(created_at: :desc).first
            recurring_fees = renewal_invoice.fees.charge
            expect(recurring_fees.count).to eq 5
            expect(recurring_fees).to all(have_attributes(units: 1))
            expect(recurring_fees.map(&:amount_cents).sort).to eq([20, 19, 18, 17, 16].sort.map { |i| i * 100 })
          end
        end
      end
    end
  end
end
