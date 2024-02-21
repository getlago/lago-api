# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:minimum_commitment_invoice_display_name) { 'Minimum spending' }
  let(:minimum_commitment_amount_cents) { 100 }
  let(:commitment_tax) { create(:tax, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdatePlanInput!) {
        updatePlan(input: $input) {
          id,
          name,
          invoiceDisplayName,
          code,
          interval,
          payInAdvance,
          amountCents,
          amountCurrency,
          minimumCommitment {
            id,
            amountCents,
            invoiceDisplayName,
            taxes { id code rate }
          },
          charges {
            id,
            chargeModel,
            billableMetric { id name code },
            properties {
              amount,
              freeUnits,
              packageSize,
              rate,
              fixedAmount,
              freeUnitsPerEvents,
              freeUnitsPerTotalAggregation,
              graduatedRanges { fromValue, toValue },
              volumeRanges { fromValue, toValue }
            }
            groupProperties {
              groupId,
              values {
                amount,
                freeUnits,
                packageSize,
                rate,
                fixedAmount,
                freeUnitsPerEvents,
                freeUnitsPerTotalAggregation,
                graduatedRanges { fromValue, toValue },
                volumeRanges { fromValue, toValue }
              }
            }
          }
        }
      }
    GQL
  end

  let(:billable_metrics) do
    create_list(:billable_metric, 5, organization:)
  end

  let(:minimum_commitment) { create(:commitment, :minimum_commitment, plan:) }
  let(:first_group) { create(:group, billable_metric: billable_metrics[1]) }
  let(:second_group) { create(:group, billable_metric: billable_metrics[2]) }

  let(:graphql) do
    {
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: plan.id,
          name: 'Updated plan',
          invoiceDisplayName: 'Updated plan invoice name',
          code: 'new_plan',
          interval: 'monthly',
          payInAdvance: false,
          amountCents: '200',
          amountCurrency: 'EUR',
          minimumCommitment: {
            amountCents: minimum_commitment_amount_cents,
            invoiceDisplayName: minimum_commitment_invoice_display_name,
            taxCodes: [commitment_tax.code],
          },
          charges: [
            {
              billableMetricId: billable_metrics[0].id,
              chargeModel: 'standard',
              properties: { amount: '100.00' },
            },
            {
              billableMetricId: billable_metrics[1].id,
              chargeModel: 'package',
              groupProperties: [
                {
                  groupId: first_group.id,
                  values: {
                    amount: '300.00',
                    freeUnits: 10,
                    packageSize: 10,
                  },
                },
              ],
            },
            {
              billableMetricId: billable_metrics[2].id,
              chargeModel: 'percentage',
              groupProperties: [
                {
                  groupId: second_group.id,
                  values: {
                    rate: '0.25',
                    fixedAmount: '2',
                    freeUnitsPerEvents: 5,
                    freeUnitsPerTotalAggregation: '50',
                  },
                },
              ],
            },
            {
              billableMetricId: billable_metrics[3].id,
              chargeModel: 'graduated',
              properties: {
                graduatedRanges: [
                  {
                    fromValue: 0,
                    toValue: 10,
                    perUnitAmount: '2.00',
                    flatAmount: '0',
                  },
                  {
                    fromValue: 11,
                    toValue: nil,
                    perUnitAmount: '3.00',
                    flatAmount: '3.00',
                  },
                ],
              },
            },
            {
              billableMetricId: billable_metrics[4].id,
              chargeModel: 'volume',
              properties: {
                volumeRanges: [
                  {
                    fromValue: 0,
                    toValue: 10,
                    perUnitAmount: '2.00',
                    flatAmount: '0',
                  },
                  {
                    fromValue: 11,
                    toValue: nil,
                    perUnitAmount: '3.00',
                    flatAmount: '3.00',
                  },
                ],
              },
            },
          ],
        },
      },
    }
  end

  before { minimum_commitment }

  context 'with premium license' do
    around { |test| lago_premium!(&test) }

    it 'updates a plan' do
      result = execute_graphql(**graphql)

      result_data = result['data']['updatePlan']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['name']).to eq('Updated plan')
        expect(result_data['invoiceDisplayName']).to eq('Updated plan invoice name')
        expect(result_data['code']).to eq('new_plan')
        expect(result_data['interval']).to eq('monthly')
        expect(result_data['payInAdvance']).to eq(false)
        expect(result_data['amountCents']).to eq('200')
        expect(result_data['amountCurrency']).to eq('EUR')
        expect(result_data['charges'].count).to eq(5)

        standard_charge = result_data['charges'][0]
        expect(standard_charge['properties']['amount']).to eq('100.00')
        expect(standard_charge['chargeModel']).to eq('standard')

        package_charge = result_data['charges'][1]
        expect(package_charge['chargeModel']).to eq('package')
        group_properties = package_charge['groupProperties'][0]['values']
        expect(group_properties['amount']).to eq('300.00')
        expect(group_properties['freeUnits']).to eq('10')
        expect(group_properties['packageSize']).to eq('10')

        percentage_charge = result_data['charges'][2]
        expect(percentage_charge['chargeModel']).to eq('percentage')
        group_properties = percentage_charge['groupProperties'][0]['values']
        expect(group_properties['rate']).to eq('0.25')
        expect(group_properties['fixedAmount']).to eq('2')
        expect(group_properties['freeUnitsPerEvents']).to eq('5')
        expect(group_properties['freeUnitsPerTotalAggregation']).to eq('50')

        graduated_charge = result_data['charges'][3]
        expect(graduated_charge['chargeModel']).to eq('graduated')
        expect(graduated_charge['properties']['graduatedRanges'].count).to eq(2)

        volume_charge = result_data['charges'][4]
        expect(volume_charge['chargeModel']).to eq('volume')
        expect(volume_charge['properties']['volumeRanges'].count).to eq(2)

        expect(result_data['minimumCommitment']).to include(
          'invoiceDisplayName' => minimum_commitment_invoice_display_name,
          'amountCents' => minimum_commitment_amount_cents.to_s,
        )
        expect(result_data['minimumCommitment']['taxes'].count).to eq(1)
      end
    end

    it 'updates minimum commitment' do
      result = execute_graphql(**graphql)

      result_data = result['data']['updatePlan']

      aggregate_failures do
        expect(result_data['minimumCommitment']).to include(
          'invoiceDisplayName' => minimum_commitment_invoice_display_name,
          'amountCents' => minimum_commitment_amount_cents.to_s,
        )
        expect(result_data['minimumCommitment']['taxes'].count).to eq(1)
      end
    end
  end

  context 'without premium license' do
    it 'updates a plan' do
      result = execute_graphql(**graphql)

      result_data = result['data']['updatePlan']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['name']).to eq('Updated plan')
        expect(result_data['invoiceDisplayName']).to eq('Updated plan invoice name')
        expect(result_data['code']).to eq('new_plan')
        expect(result_data['interval']).to eq('monthly')
        expect(result_data['payInAdvance']).to eq(false)
        expect(result_data['amountCents']).to eq('200')
        expect(result_data['amountCurrency']).to eq('EUR')
        expect(result_data['charges'].count).to eq(5)

        standard_charge = result_data['charges'][0]
        expect(standard_charge['properties']['amount']).to eq('100.00')
        expect(standard_charge['chargeModel']).to eq('standard')

        package_charge = result_data['charges'][1]
        expect(package_charge['chargeModel']).to eq('package')
        group_properties = package_charge['groupProperties'][0]['values']
        expect(group_properties['amount']).to eq('300.00')
        expect(group_properties['freeUnits']).to eq('10')
        expect(group_properties['packageSize']).to eq('10')

        percentage_charge = result_data['charges'][2]
        expect(percentage_charge['chargeModel']).to eq('percentage')
        group_properties = percentage_charge['groupProperties'][0]['values']
        expect(group_properties['rate']).to eq('0.25')
        expect(group_properties['fixedAmount']).to eq('2')
        expect(group_properties['freeUnitsPerEvents']).to eq('5')
        expect(group_properties['freeUnitsPerTotalAggregation']).to eq('50')

        graduated_charge = result_data['charges'][3]
        expect(graduated_charge['chargeModel']).to eq('graduated')
        expect(graduated_charge['properties']['graduatedRanges'].count).to eq(2)

        volume_charge = result_data['charges'][4]
        expect(volume_charge['chargeModel']).to eq('volume')
        expect(volume_charge['properties']['volumeRanges'].count).to eq(2)
      end
    end

    it 'does not update minimum commitment' do
      result = execute_graphql(**graphql)

      result_data = result['data']['updatePlan']

      aggregate_failures do
        expect(result_data['minimumCommitment']).to include(
          'invoiceDisplayName' => minimum_commitment.invoice_display_name,
          'amountCents' => minimum_commitment.amount_cents.to_s,
        )
      end
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: plan.id,
            name: 'Updated plan',
            code: 'new_plan',
            interval: 'monthly',
            payInAdvance: false,
            amountCents: 200,
            amountCurrency: 'EUR',
            charges: [],
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
