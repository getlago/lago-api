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
    let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
    let(:cache) { Rails.cache }

    before do
      subscription
      create(:standard_charge, plan: plan, charge_model: 'standard')
      allow(Rails).to receive(:cache).and_return(memory_store)
      Rails.cache.clear
    end

    it 'uses the Rails cache' do
      key = "current_usage/#{subscription.id}-#{subscription.created_at.iso8601}/#{subscription.plan.updated_at.iso8601}"

      expect do
        invoice_service.usage
      end.to change { cache.exist?(key) }.from(false).to(true)
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

      context 'when subscription is billed on anniversary date' do
        let(:current_date) { DateTime.parse('2022-06-22') }
        let(:started_at) { DateTime.parse('2022-03-07') }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            customer: customer,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
          )
        end

        it 'initialize an invoice' do
          travel_to(current_date) do
            result = invoice_service.usage

            aggregate_failures do
              expect(result).to be_success

              expect(result.usage.id).to be_nil
              expect(result.usage.from_date.to_date.to_s).to eq('2022-06-07')
              expect(result.usage.to_date.to_date.to_s).to eq('2022-07-06')
              expect(result.usage.issuing_date).to eq('2022-07-06')
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
      end
    end

    context 'when billed weekly' do
      let(:plan) { create(:plan, interval: 'weekly') }

      it 'intialize an invoice' do
        result = invoice_service.usage

        aggregate_failures do
          expect(result).to be_success

          expect(result.usage.id).to be_nil
          expect(result.usage.from_date).to eq(Time.zone.today.beginning_of_week.iso8601)
          expect(result.usage.to_date).to eq(Time.zone.today.end_of_week.iso8601)
          expect(result.usage.issuing_date).to eq(Time.zone.today.end_of_week.iso8601)
          expect(result.usage.fees.size).to eq(1)

          expect(result.usage.amount_cents).to eq(0)
          expect(result.usage.amount_currency).to eq('EUR')
          expect(result.usage.vat_amount_cents).to eq(0)
          expect(result.usage.vat_amount_currency).to eq('EUR')
          expect(result.usage.total_amount_cents).to eq(0)
          expect(result.usage.total_amount_currency).to eq('EUR')
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:current_date) { DateTime.parse('2022-06-22') }
        let(:started_at) { DateTime.parse('2022-03-07') }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            customer: customer,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
          )
        end

        it 'initialize an invoice' do
          travel_to(current_date) do
            result = invoice_service.usage

            aggregate_failures do
              expect(result).to be_success

              expect(result.usage.id).to be_nil
              expect(result.usage.from_date.to_date.to_s).to eq('2022-06-20')
              expect(result.usage.to_date.to_date.to_s).to eq('2022-06-26')
              expect(result.usage.issuing_date).to eq('2022-06-26')
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

      context 'when subscription is billed on anniversary date' do
        let(:current_date) { DateTime.parse('2022-06-22') }
        let(:started_at) { DateTime.parse('2021-03-07') }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            customer: customer,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
          )
        end

        it 'initialize an invoice' do
          travel_to(current_date) do
            result = invoice_service.usage

            aggregate_failures do
              expect(result).to be_success

              expect(result.usage.id).to be_nil
              expect(result.usage.from_date.to_date.to_s).to eq('2022-03-07')
              expect(result.usage.to_date.to_date.to_s).to eq('2023-03-06')
              expect(result.usage.issuing_date).to eq('2023-03-06')
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
      end
    end

    context 'when customer is not found' do
      let(:customer_id) { 'foo' }

      it 'returns an error' do
        result = invoice_service.usage

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when no_active_subscription' do
      let(:subscription) { nil }

      it 'fails' do
        result = invoice_service.usage

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq('no_active_subscription')
        end
      end
    end
  end
end
