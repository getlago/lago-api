# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CustomerUsageService, type: :service do
  subject(:invoice_service) do
    described_class.new(membership.user, customer_id: customer_id, subscription_id: subscription_id)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_id) {}
  let(:subscription_id) { nil }

  describe '.usage' do
    let(:billable_metric) do
      create(:billable_metric, aggregation_type: 'count_agg')
    end

    let(:customer) { create(:customer, organization: organization) }
    let(:customer_id) { customer.id }
    let(:subscription_id) { subscription&.id }
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        customer: customer,
        started_at: Time.zone.now - 2.years,
      )
    end
    let(:plan) { create(:plan, interval: 'monthly') }

    before do
      subscription
      create(:standard_charge, plan: plan, charge_model: 'standard')
    end

    context 'when billed monthly' do
      it 'initialize an invoice' do
        result = invoice_service.usage

        aggregate_failures do
          expect(result).to be_success

          expect(result.usage.id).to be_nil
          expect(result.usage.from_date).to eq(Time.zone.today.beginning_of_month.iso8601)
          expect(result.usage.to_date).to eq(Time.zone.today.end_of_month.iso8601)
          expect(result.usage.issuing_date).to eq(Time.zone.today.end_of_month.iso8601)
          expect(result.usage.fees.size).to eq(1)

          expect(result.usage.amount_cents).to eq(0)
          expect(result.usage.amount_currency).to eq('EUR')
          expect(result.usage.vat_amount_cents).to eq(0)
          expect(result.usage.vat_amount_currency).to eq('EUR')
          expect(result.usage.total_amount_cents).to eq(0)
          expect(result.usage.total_amount_currency).to eq('EUR')
        end
      end

      context 'with subscription started in current billing period' do
        before { subscription.update!(started_at: Time.zone.today) }

        it 'changes the from date of the invoice' do
          result = invoice_service.usage

          aggregate_failures do
            expect(result).to be_success

            expect(result.usage.id).to be_nil
            expect(result.usage.from_date).to eq(subscription.started_at.to_date.iso8601)
          end
        end
      end
    end

    context 'when billed yearly' do
      let(:plan) { create(:plan, interval: 'yearly') }

      it 'intialize an invoice' do
        result = invoice_service.usage

        aggregate_failures do
          expect(result).to be_success

          expect(result.usage.id).to be_nil
          expect(result.usage.from_date).to eq(Time.zone.today.beginning_of_year.iso8601)
          expect(result.usage.to_date).to eq(Time.zone.today.end_of_year.iso8601)
          expect(result.usage.issuing_date).to eq(Time.zone.today.end_of_year.iso8601)
          expect(result.usage.fees.size).to eq(1)

          expect(result.usage.amount_cents).to eq(0)
          expect(result.usage.amount_currency).to eq('EUR')
          expect(result.usage.vat_amount_cents).to eq(0)
          expect(result.usage.vat_amount_currency).to eq('EUR')
          expect(result.usage.total_amount_cents).to eq(0)
          expect(result.usage.total_amount_currency).to eq('EUR')
        end
      end
    end

    context 'when customer is not found' do
      let(:customer_id) { 'foo' }

      it 'returns an error' do
        result = invoice_service.usage

        expect(result).not_to be_success
        expect(result.error_code).to eq('not_found')
      end
    end

    context 'when no_active_subscription' do
      let(:subscription) { nil }

      it 'returns an error' do
        result = invoice_service.usage

        expect(result).not_to be_success
        expect(result.error_code).to eq('no_active_subscription')
      end
    end
  end
end
