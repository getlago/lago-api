# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PreviewService, type: :service, cache: :memory do
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

      context 'with credit note credits' do
        let(:credit_note) do
          create(
            :credit_note,
            customer:,
            total_amount_cents: 2,
            total_amount_currency: plan.amount_currency,
            balance_amount_cents: 2,
            balance_amount_currency: plan.amount_currency,
            credit_amount_cents: 2,
            credit_amount_currency: plan.amount_currency
          )
        end

        before { credit_note }

        it 'creates preview invoice for 2 days with credits included' do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).to be_success
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.invoice_type).to eq('subscription')
            expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
            expect(result.invoice.fees_amount_cents).to eq(6)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
            expect(result.invoice.taxes_amount_cents).to eq(3)
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
            expect(result.invoice.credit_notes_amount_cents).to eq(2)
            expect(result.invoice.total_amount_cents).to eq(7)
          end
        end
      end

      context 'with wallet credits' do
        let(:wallet) { build(:wallet, customer:, balance: '0.03', credits_balance: '0.03') }

        before { wallet }

        context 'with customer that is not persisted' do
          it 'does not apply credits' do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.total_amount_cents).to eq(9)
              expect(result.invoice.prepaid_credit_amount_cents).to eq(0)
            end
          end
        end

        context 'with customer that is persisted' do
          let(:customer) { create(:customer, organization:) }
          let(:wallet) { create(:wallet, customer:, balance: '0.03', credits_balance: '0.03') }

          it 'applies credits' do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq('subscription')
              expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
              expect(result.invoice.taxes_amount_cents).to eq(3)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
              expect(result.invoice.prepaid_credit_amount_cents).to eq(3)
              expect(result.invoice.total_amount_cents).to eq(6)
            end
          end
        end
      end

      context 'with provider taxes' do
        let(:integration) { create(:anrok_integration, organization:) }
        let(:integration_customer) { build(:anrok_customer, integration:, customer:) }
        let(:response) { instance_double(Net::HTTPOK) }
        let(:lago_client) { instance_double(LagoHttpClient::Client) }
        let(:endpoint) { 'https://api.nango.dev/v1/anrok/draft_invoices' }
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response.json')
          File.read(p)
        end
        let(:integration_collection_mapping) do
          create(
            :netsuite_collection_mapping,
            integration:,
            mapping_type: :fallback_item,
            settings: {external_id: '1', external_account_code: '11', external_name: ''}
          )
        end

        before do
          integration_collection_mapping
          customer.integration_customers = [integration_customer]

          allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
          allow(lago_client).to receive(:post_with_response).and_return(response)
          allow(response).to receive(:body).and_return(body)
          allow_any_instance_of(Fee).to receive(:id).and_return('lago_fee_id') # rubocop:disable RSpec/AnyInstance
        end

        it 'creates preview invoice for 2 days' do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).to be_success
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.invoice_type).to eq('subscription')
            expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
            expect(result.invoice.fees_amount_cents).to eq(6)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
            expect(result.invoice.taxes_amount_cents).to eq(1) # 6 x 0.1
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(7)
            expect(result.invoice.total_amount_cents).to eq(7)
          end
        end

        context 'when there is error received from the provider' do
          let(:body) do
            p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
            File.read(p)
          end

          it 'uses zero taxes' do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq('subscription')
              expect(result.invoice.issuing_date.to_s).to eq('2024-04-01')
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
              expect(result.invoice.taxes_amount_cents).to eq(0)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(6)
              expect(result.invoice.total_amount_cents).to eq(6)
            end
          end
        end

        context 'with rails cache' do
          let(:customer) { create(:customer, organization:) }

          before { Rails.cache.clear }

          it 'uses the Rails cache' do
            travel_to(timestamp) do
              key = [
                'preview-taxes',
                customer.id,
                plan.updated_at.iso8601
              ].join('/')

              expect do
                preview_service.call
              end.to change { Rails.cache.exist?(key) }.from(false).to(true)
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
