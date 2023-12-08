# frozen_string_literal: true

require 'rails_helper'

describe 'Charge Models - Prorated Graduated Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, name: 'aaaaaabcd') }
  let(:tax) { create(:tax, organization:, rate: 0) }

  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:billable_metric) { create(:billable_metric, recurring: true, organization:, aggregation_type:, field_name:) }

  before { tax }

  describe 'with sum_agg' do
    let(:aggregation_type) { 'sum_agg' }
    let(:field_name) { 'amount' }

    describe 'three ranges and one overflow case' do
      it 'returns the expected invoice and usage amounts' do
        Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
        WebhookEndpoint.destroy_all

        travel_to(DateTime.new(2023, 9, 1)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :graduated_charge,
          billable_metric:,
          prorated: true,
          plan:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 5,
                per_unit_amount: '10',
                flat_amount: '100',
              },
              {
                from_value: 6,
                to_value: 15,
                per_unit_amount: '5',
                flat_amount: '50',
              },
              {
                from_value: 16,
                to_value: nil,
                per_unit_amount: '2',
                flat_amount: '0',
              },
            ],
          },
        )

        fetch_current_usage(customer:)
        expect(json[:customer_usage][:amount_cents].round(2)).to eq(0)
        expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(0)
        expect(json[:customer_usage][:charges_usage][0][:units]).to eq('0.0')

        travel_to(DateTime.new(2023, 9, 10)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '2' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(11_400)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(11_400)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')
        end

        travel_to(DateTime.new(2023, 9, 16)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '5' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(18_400)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(18_400)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('7.0')
        end

        travel_to(DateTime.new(2023, 9, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '-6' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(16_567)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(16_567)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')
        end

        travel_to(DateTime.new(2023, 9, 25)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '10' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(17_967)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(17_967)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('11.0')
        end

        travel_to(DateTime.new(2023, 9, 26)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(18_300)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(18_300)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('15.0')
        end

        travel_to(DateTime.new(2023, 9, 30)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '60' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(18_700)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(18_700)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
        end

        travel_to(DateTime.new(2023, 10, 1)) do
          Subscriptions::BillingService.new.call

          perform_all_enqueued_jobs

          subscription = customer.subscriptions.first
          invoice = subscription.invoices.first

          aggregate_failures do
            expect(invoice.total_amount_cents).to eq(18_700)
            expect(subscription.reload.invoices.count).to eq(1)
          end
        end

        travel_to(DateTime.new(2023, 10, 5)) do
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(37_000)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(37_000)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
        end

        travel_to(DateTime.new(2023, 10, 17)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '20' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(38_935)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(38_935)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('95.0')
        end
      end

      context 'when there are old events before first invoice' do
        it 'returns expected invoice and usage amounts' do
          Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
          WebhookEndpoint.destroy_all

          travel_to(DateTime.new(2023, 12, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
              },
            )
          end

          subscription = customer.subscriptions.active.order(created_at: :desc).first

          create(
            :graduated_charge,
            billable_metric:,
            prorated: true,
            plan:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 5,
                  per_unit_amount: '0',
                  flat_amount: '0',
                },
                {
                  from_value: 6,
                  to_value: nil,
                  per_unit_amount: '12',
                  flat_amount: '0',
                },
              ],
            },
          )

          travel_to(DateTime.new(2023, 12, 2)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                timestamp: 1_699_336_493, ## November 2023
                external_subscription_id: subscription.external_id,
                properties: { amount: '5' },
              },
            )

            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                timestamp: 1_699_336_493, ## November 2023
                external_subscription_id: subscription.external_id,
                properties: { amount: '5' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(6_000)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(6_000)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('10.0')
          end

          travel_to(DateTime.new(2024, 1, 1)) do
            Subscriptions::BillingService.new.call

            perform_all_enqueued_jobs

            subscription = customer.subscriptions.first
            invoice = subscription.invoices.first

            aggregate_failures do
              expect(invoice.total_amount_cents).to eq(6_000)
              expect(subscription.reload.invoices.count).to eq(1)
            end
          end

          travel_to(DateTime.new(2024, 1, 5)) do
            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(6_000)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(6_000)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('10.0')
          end

          travel_to(DateTime.new(2024, 1, 6)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '2' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(8_013)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(8_013)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('12.0')
          end
        end
      end

      context 'when there are old events before first invoice and subscription is terminated' do
        it 'returns expected invoice and usage amounts' do
          Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
          WebhookEndpoint.destroy_all

          travel_to(DateTime.new(2023, 10, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
              },
            )
          end

          subscription = customer.subscriptions.active.order(created_at: :desc).first

          create(
            :graduated_charge,
            billable_metric:,
            prorated: true,
            plan:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 5,
                  per_unit_amount: '0',
                  flat_amount: '0',
                },
                {
                  from_value: 6,
                  to_value: nil,
                  per_unit_amount: '10',
                  flat_amount: '0',
                },
              ],
            },
          )

          travel_to(DateTime.new(2023, 10, 5)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '4' },
              },
            )

            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '3' },
              },
            )
          end

          travel_to(DateTime.new(2023, 11, 5)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '-1' },
              },
            )
          end

          travel_to(DateTime.new(2023, 12, 7)) do
            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(1_000)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(1_000)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('6.0')

            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '1' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(1_806)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(1_806)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('7.0')

            Subscriptions::TerminateService.call(subscription:)
            perform_all_enqueued_jobs
            invoice = subscription.invoices.order(created_at: :desc).first

            aggregate_failures do
              expect(subscription.reload).to be_terminated
              expect(subscription.reload.invoices.count).to eq(1)
              expect(invoice.total_amount_cents).to eq(226)
              expect(invoice.issuing_date.iso8601).to eq('2023-12-07')
            end
          end
        end
      end

      context 'when upgrade is performed' do
        let(:plan_new) { create(:plan, organization:, amount_cents: 100) }

        it 'returns expected invoice and usage amounts' do
          Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
          WebhookEndpoint.destroy_all

          travel_to(DateTime.new(2023, 9, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
              },
            )
          end

          create(
            :graduated_charge,
            billable_metric:,
            prorated: true,
            plan:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 5,
                  per_unit_amount: '10',
                  flat_amount: '100',
                },
                {
                  from_value: 6,
                  to_value: 15,
                  per_unit_amount: '5',
                  flat_amount: '50',
                },
                {
                  from_value: 16,
                  to_value: nil,
                  per_unit_amount: '2',
                  flat_amount: '0',
                },
              ],
            },
          )

          travel_to(DateTime.new(2023, 9, 10)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '2' },
              },
            )
          end

          travel_to(DateTime.new(2023, 9, 16)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '5' },
              },
            )
          end

          travel_to(DateTime.new(2023, 9, 20)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '-6' },
              },
            )
          end

          travel_to(DateTime.new(2023, 9, 25)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '10' },
              },
            )
          end

          travel_to(DateTime.new(2023, 9, 26)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '4' },
              },
            )
          end

          travel_to(DateTime.new(2023, 9, 30)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '60' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(18_700)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(18_700)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
          end

          travel_to(DateTime.new(2023, 10, 1)) do
            Subscriptions::BillingService.new.call

            perform_all_enqueued_jobs

            subscription = customer.subscriptions.first
            invoice = subscription.invoices.first

            aggregate_failures do
              expect(invoice.total_amount_cents).to eq(18_700)
              expect(subscription.reload.invoices.count).to eq(1)
            end
          end

          travel_to(DateTime.new(2023, 10, 5)) do
            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(37_000)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(37_000)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
          end

          travel_to(DateTime.new(2023, 10, 17)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_customer_id: customer.external_id,
                properties: { amount: '20' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(38_935)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(38_935)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('95.0')
          end

          subscription = customer.subscriptions.first

          travel_to(DateTime.new(2023, 10, 18)) do
            create(
              :graduated_charge,
              billable_metric:,
              prorated: true,
              plan: plan_new,
              properties: {
                graduated_ranges: [
                  {
                    from_value: 0,
                    to_value: 5,
                    per_unit_amount: '10',
                    flat_amount: '100',
                  },
                  {
                    from_value: 6,
                    to_value: 15,
                    per_unit_amount: '5',
                    flat_amount: '50',
                  },
                  {
                    from_value: 16,
                    to_value: nil,
                    per_unit_amount: '2',
                    flat_amount: '0',
                  },
                ],
              },
            )
            expect {
              create_subscription(
                {
                  external_customer_id: customer.external_id,
                  external_id: customer.external_id,
                  plan_code: plan_new.code,
                },
              )
            }.to change { subscription.reload.status }.from('active').to('terminated')
              .and change { subscription.invoices.count }.from(1).to(2)

            invoice = subscription.invoices.order(created_at: :desc).first
            expect(invoice.fees.charge_kind.count).to eq(1)
            # 30226 (17 / 31 * 75 units) + 2.58 = 2 / 31 * 20 units (prorated event in termination period)
            expect(invoice.total_amount_cents).to eq(27_323)
          end

          travel_to(DateTime.new(2023, 11, 1)) do
            Subscriptions::BillingService.new.call

            perform_all_enqueued_jobs

            subscription = customer.subscriptions.order(created_at: :desc).first
            invoice = subscription.invoices.order(created_at: :desc).first

            aggregate_failures do
              # (95 units * 14/31) -> 26_742 - charge fee
              # 100 * 14/31 -> 45 -> subscription fee
              expect(invoice.total_amount_cents).to eq(26_742 + 45)
              expect(subscription.reload.invoices.count).to eq(1)
            end
          end

          travel_to(DateTime.new(2023, 11, 5)) do
            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(41_000)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(41_000)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('95.0')
          end
        end
      end
    end
  end

  describe 'with unique_count_agg' do
    let(:aggregation_type) { 'unique_count_agg' }
    let(:field_name) { 'amount' }

    describe 'two ranges' do
      it 'returns the expected invoice and usage amounts' do
        Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
        WebhookEndpoint.destroy_all

        travel_to(DateTime.new(2023, 9, 1)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :graduated_charge,
          billable_metric:,
          prorated: true,
          plan:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 1,
                per_unit_amount: '10',
                flat_amount: '100',
              },
              {
                from_value: 2,
                to_value: nil,
                per_unit_amount: '5',
                flat_amount: '50',
              },
            ],
          },
        )

        travel_to(DateTime.new(2023, 9, 10)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1111', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(10_700)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(10_700)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')
        end

        travel_to(DateTime.new(2023, 9, 12)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1111', operation_type: 'remove' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(10_100)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(10_100)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('0.0')
        end

        travel_to(DateTime.new(2023, 9, 14)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1111', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(15_383)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(15_383)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')
        end

        travel_to(DateTime.new(2023, 9, 15)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '2222', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(15_650)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(15_650)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')
        end

        travel_to(DateTime.new(2023, 9, 16)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '2222', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(15_650)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(15_650)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')
        end

        travel_to(DateTime.new(2023, 9, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '3333', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(15_833)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(15_833)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('3.0')
        end

        travel_to(DateTime.new(2023, 10, 1)) do
          Subscriptions::BillingService.new.call

          perform_all_enqueued_jobs

          subscription = customer.subscriptions.first
          invoice = subscription.invoices.first

          aggregate_failures do
            expect(invoice.total_amount_cents).to eq(15_833)
            expect(subscription.reload.invoices.count).to eq(1)
          end
        end

        travel_to(DateTime.new(2023, 10, 5)) do
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(17_000)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(17_000)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('3.0')
        end

        travel_to(DateTime.new(2023, 10, 17)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4444', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(17_242)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(17_242)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('4.0')
        end
      end
    end

    context 'with multiple events on the same day' do
      it 'returns the expected invoice and usage amounts' do
        Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
        WebhookEndpoint.destroy_all

        travel_to(DateTime.new(2023, 9, 1)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        end

        create(
          :graduated_charge,
          billable_metric:,
          prorated: true,
          plan:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 5,
                per_unit_amount: '10',
                flat_amount: '100',
              },
              {
                from_value: 6,
                to_value: nil,
                per_unit_amount: '5',
                flat_amount: '50',
              },
            ],
          },
        )

        travel_to(DateTime.new(2023, 10, 10)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '1111', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(10_710)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(10_710)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')
        end

        travel_to(DateTime.new(2023, 10, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '2222', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(11_097)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(11_097)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')
        end

        travel_to(DateTime.new(2023, 10, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '3333', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(11_484)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(11_484)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('3.0')
        end

        travel_to(DateTime.new(2023, 10, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '4444', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(11_871)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(11_871)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('4.0')
        end

        travel_to(DateTime.new(2023, 10, 20)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '5555', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(12_258)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(12_258)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('5.0')
        end

        travel_to(DateTime.new(2023, 10, 25)) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_customer_id: customer.external_id,
              properties: { amount: '6666', operation_type: 'add' },
            },
          )

          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(17_371)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(17_371)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('6.0')
        end

        travel_to(DateTime.new(2023, 11, 1)) do
          Subscriptions::BillingService.new.call

          perform_all_enqueued_jobs

          subscription = customer.subscriptions.first
          invoice = subscription.invoices.first

          aggregate_failures do
            expect(invoice.total_amount_cents).to eq(17_371)
            expect(subscription.reload.invoices.count).to eq(1)
          end
        end

        travel_to(DateTime.new(2023, 11, 5)) do
          fetch_current_usage(customer:)
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(20_500)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(20_500)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('6.0')
        end
      end

      context 'when there are old events before first invoice and subscription is terminated' do
        it 'returns expected invoice and usage amounts' do
          Organization.update_all(webhook_url: nil) # rubocop:disable Rails/SkipsModelValidations
          WebhookEndpoint.destroy_all

          travel_to(DateTime.new(2023, 10, 1)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
              },
            )
          end

          subscription = customer.subscriptions.active.order(created_at: :desc).first

          create(
            :graduated_charge,
            billable_metric:,
            prorated: true,
            plan:,
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 1,
                  per_unit_amount: '5',
                  flat_amount: '10',
                },
                {
                  from_value: 2,
                  to_value: nil,
                  per_unit_amount: '15',
                  flat_amount: '30',
                },
              ],
            },
          )

          travel_to(DateTime.new(2023, 10, 5)) do
            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '1111', operation_type: 'add' },
              },
            )
          end

          travel_to(DateTime.new(2023, 12, 7)) do
            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(1_500)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(1_500)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('1.0')

            create_event(
              {
                code: billable_metric.code,
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                properties: { amount: '2222', operation_type: 'add' },
              },
            )

            fetch_current_usage(customer:)
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(5_710)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(5_710)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('2.0')

            Subscriptions::TerminateService.call(subscription:)
            perform_all_enqueued_jobs
            invoice = subscription.invoices.order(created_at: :desc).first

            aggregate_failures do
              expect(subscription.reload).to be_terminated
              expect(subscription.reload.invoices.count).to eq(1)
              expect(invoice.total_amount_cents).to eq(4_145)
              expect(invoice.issuing_date.iso8601).to eq('2023-12-07')
            end
          end
        end
      end
    end
  end
end
