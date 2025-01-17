# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PreviewService, type: :service do
  subject(:preview_service) { described_class.new(customer:, subscription:) }

  describe '#call' do
    let(:organization) { create(:organization) }
    let(:tax) { create(:tax, rate: 50.0, organization:) }
    let(:customer) { build(:customer, organization:) }
    let(:timestamp) { Time.zone.parse('30 Mar 2024') }
    let(:plan) { create(:plan, organization:, interval: 'monthly') }
    let(:billing_time) { 'calendar' }
    let(:subscription) do
      build(
        :subscription,
        customer:,
        plan:,
        billing_time:,
        subscription_at: timestamp,
        started_at: timestamp,
        created_at: timestamp
      )
    end

    before { tax }

    context 'when customer does not exist' do
      it 'returns an error' do
        result = described_class.new(customer: nil, subscription:).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when subscription does not exist' do
      it 'returns an error' do
        result = described_class.new(customer:, subscription: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('subscription_not_found')
      end
    end

    context 'with calendar billing' do
      it 'creates preview invoice for 2 days' do
        # Two days should be billed, Mar 30 and Mar 31

        travel_to(timestamp) do
          result = preview_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.invoice_type).to eq('subscription')
            expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
            expect(result.invoice.fees_amount_cents).to eq(6)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
            expect(result.invoice.taxes_amount_cents).to eq(3)
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
            expect(result.invoice.total_amount_cents).to eq(9)
          end
        end
      end

      context 'with applied coupons' do
        let(:applied_coupon) do
          build(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 2,
            amount_currency: plan.amount_currency
          )
        end

        it 'creates preview invoice for 2 days with applied coupons' do
          travel_to(timestamp) do
            result = described_class.new(customer:, subscription:, applied_coupons: [applied_coupon]).call

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq('subscription')
              expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.coupons_amount_cents).to eq(2)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(4)
              expect(result.invoice.taxes_amount_cents).to eq(2)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(6)
              expect(result.invoice.total_amount_cents).to eq(6)
              expect(result.invoice.credits.length).to eq(1)
            end
          end
        end
      end
    end

    context 'with anniversary billing' do
      let(:billing_time) { 'anniversary' }

      it 'creates preview invoice for full month' do
        travel_to(timestamp) do
          result = preview_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.invoice_type).to eq('subscription')
            expect(result.invoice.issuing_date.to_s).to eq('2024-04-30')
            expect(result.invoice.fees_amount_cents).to eq(100)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
            expect(result.invoice.taxes_amount_cents).to eq(50)
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(150)
            expect(result.invoice.total_amount_cents).to eq(150)
          end
        end
      end
    end
  end
end
