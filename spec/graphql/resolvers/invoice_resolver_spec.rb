# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoiceResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        invoice(id: $id) {
          id
          number
          feesAmountCents
          couponsAmountCents
          creditNotesAmountCents
          prepaidCreditAmountCents
          refundableAmountCents
          creditableAmountCents
          paymentDisputeLosable
          paymentStatus
          status
          customer {
            id
            name
            deletedAt
          }
          appliedTaxes {
            taxCode
            taxName
            taxRate
            taxDescription
            amountCents
            amountCurrency
          }
          invoiceSubscriptions {
            fromDatetime
            toDatetime
            chargesFromDatetime
            chargesToDatetime
            subscription {
              id
            }
            fees {
              currency
              id
              itemType
              itemCode
              itemName
              charge { id billableMetric { code } }
              taxesRate
              taxesAmountCents
              trueUpFee { id }
              trueUpParentFee { id }
              units
              preciseUnitAmount
              filterDisplayName
              appliedTaxes {
                taxCode
                taxName
                taxRate
                taxDescription
                amountCents
                amountCurrency
              }
            }
          }
          subscriptions {
            id
          }
          fees {
            id
            itemType
            itemCode
            itemName
            creditableAmountCents
            filterDisplayName
            charge {
              id
              billableMetric {
                code
                filters { key values }
              }
              filters { invoiceDisplayName values }
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:) }
  let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10) }
  let(:subscription) { invoice_subscription.subscription }
  let(:fee) { create(:fee, subscription:, invoice:, amount_cents: 10) }

  before { fee and invoice }

  it 'returns a single invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        id: invoice.id,
      },
    )

    data = result['data']['invoice']

    aggregate_failures do
      expect(data['id']).to eq(invoice.id)
      expect(data['number']).to eq(invoice.number)
      expect(data['paymentStatus']).to eq(invoice.payment_status)
      expect(data['paymentDisputeLosable']).to eq(true)
      expect(data['status']).to eq(invoice.status)
      expect(data['customer']['id']).to eq(customer.id)
      expect(data['customer']['name']).to eq(customer.name)
      expect(data['invoiceSubscriptions'][0]['subscription']['id']).to eq(subscription.id)
      expect(data['invoiceSubscriptions'][0]['fees'][0]['id']).to eq(fee.id)
    end
  end

  it 'includes filters for each fee' do
    billable_metric_filter = create(:billable_metric_filter, key: 'cloud', values: %w[aws gcp])
    charge_filter = create(:charge_filter, invoice_display_name: nil)
    charge_filter_value = create(:charge_filter_value, billable_metric_filter:, charge_filter:, values: ['aws'])

    fee.update!(charge_filter_id: charge_filter.id)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { id: invoice.id },
    )

    expect(
      result['data']['invoice']['invoiceSubscriptions'][0]['fees'][0]['filterDisplayName'],
    ).to eq(charge_filter_value.values.first)
  end

  context 'when invoice is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: invoice.organization,
        query:,
        variables: {
          id: 'foo',
        },
      )

      expect_graphql_error(result:, message: 'Resource not found')
    end
  end

  context 'with a deleted billable metric' do
    let(:billable_metric) { create(:billable_metric, :deleted) }
    let(:group) { create(:group, :deleted, billable_metric:) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, group:, charge:, amount_cents: 10) }

    let(:group_property) do
      build(
        :group_property,
        :deleted,
        group:,
        values: { amount: '10', amount_currency: 'EUR' },
      )
    end

    let(:charge) do
      create(:standard_charge, :deleted, billable_metric:, group_properties: [group_property])
    end

    it 'returns the invoice with the deleted resources' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          id: invoice.id,
        },
      )

      data = result['data']['invoice']

      aggregate_failures do
        expect(data['id']).to eq(invoice.id)
        expect(data['number']).to eq(invoice.number)
        expect(data['paymentStatus']).to eq(invoice.payment_status)
        expect(data['status']).to eq(invoice.status)
        expect(data['customer']['id']).to eq(customer.id)
        expect(data['customer']['name']).to eq(customer.name)
        expect(data['invoiceSubscriptions'][0]['subscription']['id']).to eq(subscription.id)
        expect(data['invoiceSubscriptions'][0]['fees'][0]['id']).to eq(fee.id)
      end
    end
  end

  context 'with an add on invoice' do
    let(:invoice) { create(:invoice, customer:, organization:, fees_amount_cents: 10) }
    let(:add_on) { create(:add_on, organization:) }
    let(:applied_add_on) { create(:applied_add_on, add_on:, customer:) }
    let(:fee) { create(:add_on_fee, invoice:, applied_add_on:) }

    it 'returns a single invoice' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          id: invoice.id,
        },
      )

      data = result['data']['invoice']

      aggregate_failures do
        expect(data['id']).to eq(invoice.id)
        expect(data['number']).to eq(invoice.number)
        expect(data['paymentStatus']).to eq(invoice.payment_status)
        expect(data['status']).to eq(invoice.status)
        expect(data['customer']['id']).to eq(customer.id)
        expect(data['customer']['name']).to eq(customer.name)
        expect(data['fees'].first).to include(
          'itemCode' => add_on.code,
          'itemName' => add_on.name,
        )
      end
    end

    context 'with a deleted add_on' do
      let(:add_on) { create(:add_on, :deleted, organization:) }

      it 'returns the invoice with the deleted resources' do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query:,
          variables: {
            id: invoice.id,
          },
        )

        data = result['data']['invoice']

        aggregate_failures do
          expect(data['id']).to eq(invoice.id)
          expect(data['number']).to eq(invoice.number)
          expect(data['paymentStatus']).to eq(invoice.payment_status)
          expect(data['status']).to eq(invoice.status)
          expect(data['customer']['id']).to eq(customer.id)
          expect(data['customer']['name']).to eq(customer.name)
          expect(data['fees'].first).to include(
            'itemType' => 'add_on',
            'itemCode' => add_on.code,
            'itemName' => add_on.name,
          )
        end
      end
    end
  end

  context 'with a deleted customer' do
    let(:customer) { create(:customer, :deleted, organization:) }

    it 'returns the invoice with the deleted customer' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          id: invoice.id,
        },
      )

      data = result['data']['invoice']

      aggregate_failures do
        expect(data['id']).to eq(invoice.id)
        expect(data['number']).to eq(invoice.number)
        expect(data['paymentStatus']).to eq(invoice.payment_status)
        expect(data['status']).to eq(invoice.status)
        expect(data['customer']['id']).to eq(customer.id)
        expect(data['customer']['name']).to eq(customer.name)
        expect(data['customer']['deletedAt']).to eq(customer.deleted_at.iso8601)
      end
    end
  end
end
