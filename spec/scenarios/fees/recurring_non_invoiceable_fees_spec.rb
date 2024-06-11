# frozen_string_literal: true

require 'rails_helper'

describe 'Recurring Non Invoiceable Fees', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:, code: 'credit_card') }
  let(:plan) { create(:plan, organization:, amount_cents: 499_00, pay_in_advance: true) }
  let(:charge) { create(:charge, plan:, billable_metric:, pay_in_advance: true, invoiceable: false, properties: {amount: '1.1'}) }

  describe 'first scenario' do
    it do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        charge
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
        perform_billing
        expect(customer.invoices.count).to eq(1)
        pp customer.subscriptions.first.fees.charge, '--------------------'

      end

      subscription =customer.subscriptions.first

      travel_to(Time.zone.parse('2024-03-06T10:00:00')) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => 'card_user_1'
            }
          }
        )

        fee = subscription.fees.charge.sole
        expect(fee.amount_cents).to eq(110)
        expect(fee.units).to eq(1)
      end

      travel_to(Time.zone.parse('2024-03-10T10:00:00')) do
        create_event(
          {
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {
              'item_id' => 'card_user_2'
            }
          }
        )
        expect(subscription.fees.charge.count).to eq(2)
        fee = subscription.fees.charge.order(created_at: :desc).first
        expect(fee.amount_cents).to eq(110)
        expect(fee.units).to eq(1)
      end

      # Send event with same item_id
      # TODO: Confirm what the behavior should be here
      # travel_to(Time.zone.parse('2024-03-12T10:00:00')) do
      #   create_event(
      #     {
      #       code: billable_metric.code,
      #       transaction_id: SecureRandom.uuid,
      #       external_subscription_id: subscription.external_id,
      #       properties: {
      #         'item_id' => 'card_user_2'
      #       }
      #     }
      #   )
      #
      #   expect(subscription.fees.charge.count).to eq(2)
      # end

      # BILLING DAY !
      travel_to(Time.zone.parse('2024-04-01T00:10:00')) do
        perform_billing

        Fee.where(subscription:, charge:).order(created_at: :desc).each do |fee|
          pp fee
        end
      end
    end
  end
end
