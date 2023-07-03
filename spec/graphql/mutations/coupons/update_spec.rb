# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Coupons::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:coupon) { create(:coupon, organization: membership.organization) }
  let(:expiration_at) { Time.current + 3.days }
  let(:plan) { create(:plan, organization: membership.organization) }
  let(:billable_metric) { create(:billable_metric, organization: membership.organization) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCouponInput!) {
        updateCoupon(input: $input) {
          id,
          name,
          code,
          description
          status,
          amountCents,
          amountCurrency,
          expiration,
          expirationAt,
          limitedPlans,
          plans {
            id
          },
          reusable
        }
      }
    GQL
  end

  it 'updates a coupon' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: coupon.id,
          name: 'New name',
          couponType: 'fixed_amount',
          frequency: 'once',
          code: 'new_code',
          description: 'This is a description',
          amountCents: 123,
          amountCurrency: 'USD',
          expiration: 'time_limit',
          expirationAt: expiration_at.iso8601,
          reusable: false,
          appliesTo: {
            planIds: [plan.id],
          },
        },
      },
    )

    result_data = result['data']['updateCoupon']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['code']).to eq('new_code')
      expect(result_data['description']).to eq('This is a description')
      expect(result_data['status']).to eq('active')
      expect(result_data['amountCents']).to eq('123')
      expect(result_data['amountCurrency']).to eq('USD')
      expect(result_data['expiration']).to eq('time_limit')
      expect(result_data['expirationAt']).to eq expiration_at.iso8601
      expect(result_data['reusable']).to eq(false)
      expect(result_data['limitedPlans']).to eq(true)
      expect(result_data['plans'].first['id']).to eq(plan.id)
    end
  end

  context 'with billable metric limitations' do
    let(:mutation) do
      <<-GQL
      mutation($input: UpdateCouponInput!) {
        updateCoupon(input: $input) {
          id,
          name,
          code,
          status,
          amountCents,
          amountCurrency,
          expiration,
          expirationAt,
          limitedBillableMetrics,
          billableMetrics {
            id
          },
          reusable
        }
      }
      GQL
    end

    it 'updates a coupon' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: coupon.id,
            name: 'New name',
            couponType: 'fixed_amount',
            frequency: 'once',
            code: 'new_code',
            amountCents: 123,
            amountCurrency: 'USD',
            expiration: 'time_limit',
            expirationAt: expiration_at.iso8601,
            reusable: false,
            appliesTo: {
              billableMetricIds: [billable_metric.id],
            },
          },
        },
      )

      result_data = result['data']['updateCoupon']

      aggregate_failures do
        expect(result_data['name']).to eq('New name')
        expect(result_data['code']).to eq('new_code')
        expect(result_data['status']).to eq('active')
        expect(result_data['amountCents']).to eq('123')
        expect(result_data['amountCurrency']).to eq('USD')
        expect(result_data['expiration']).to eq('time_limit')
        expect(result_data['expirationAt']).to eq expiration_at.iso8601
        expect(result_data['reusable']).to eq(false)
        expect(result_data['limitedBillableMetrics']).to eq(true)
        expect(result_data['billableMetrics'].first['id']).to eq(billable_metric.id)
      end
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: coupon.id,
            name: 'New name',
            code: 'new_code',
            couponType: 'fixed_amount',
            frequency: 'once',
            amountCents: 123,
            amountCurrency: 'USD',
            expiration: 'time_limit',
            expirationAt: (Time.current + 33.days).iso8601,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
