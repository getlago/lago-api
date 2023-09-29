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
          expect(json[:customer_usage][:amount_cents].round(2)).to eq(19_033)
          expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(19_033)
          expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
        end

        travel_to(DateTime.new(2023, 10, 1)) do
          Subscriptions::BillingService.new.call

          perform_all_enqueued_jobs

          subscription = customer.subscriptions.first
          invoice = subscription.invoices.first

          aggregate_failures do
            expect(invoice.total_amount_cents).to eq(19_033)
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
            expect(json[:customer_usage][:amount_cents].round(2)).to eq(19_033)
            expect(json[:customer_usage][:total_amount_cents].round(2)).to eq(19_033)
            expect(json[:customer_usage][:charges_usage][0][:units]).to eq('75.0')
          end

          travel_to(DateTime.new(2023, 10, 1)) do
            Subscriptions::BillingService.new.call

            perform_all_enqueued_jobs

            subscription = customer.subscriptions.first
            invoice = subscription.invoices.first

            aggregate_failures do
              expect(invoice.total_amount_cents).to eq(19_033)
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
            expect(invoice.total_amount_cents).to eq(30_484) # 30226 + 2.58 (prorated event in termination period)
          end

          travel_to(DateTime.new(2023, 11, 1)) do
            Subscriptions::BillingService.new.call

            perform_all_enqueued_jobs

            subscription = customer.subscriptions.order(created_at: :desc).first
            invoice = subscription.invoices.order(created_at: :desc).first

            aggregate_failures do
              # (95 units * 14/31) -> 30581 - charge fee
              # 100 * 14/31 -> 45 -> subscription fee
              expect(invoice.total_amount_cents).to eq(30_581 + 45)
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
end
