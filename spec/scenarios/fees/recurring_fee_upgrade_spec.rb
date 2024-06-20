# frozen_string_literal: true

require 'rails_helper'

describe 'Recurring Fees Subscription Upgrade', :scenarios, type: :request do # Todo name
  let(:organization) { create(:organization, webhook_url: 'http://fees.test/wh') }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:, code: 'seats') }
  let(:plan) { create(:plan, organization:, amount_cents: 49.99, pay_in_advance: true) }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:charge) do
    create(:charge, {
      plan:,
      billable_metric:,
      invoiceable:,
      pay_in_advance:,
      prorated: true,
      properties: {amount: '30', grouped_by:}
    })
  end

  def send_event!(item_id)
    create_event(
      {
        code: billable_metric.code,
        transaction_id: "tr_#{SecureRandom.hex(16)}",
        external_subscription_id:,
        properties: {'item_id' => item_id}
      }
    )
  end

  before do
    charge
    WebMock.stub_request(:post, 'http://fees.test/wh').to_return(status: 200, body: '', headers: {})
  end

  context 'when upgrading subscription' do
    let(:creation_time) { DateTime.new(2024, 6, 1, 0, 0) }
    let(:upgrade_time) { DateTime.new(2024, 6, 15, 0, 0) }
    let(:invoiceable) { false }
    let(:pay_in_advance) { true }
    let(:grouped_by) { ['item_id'] }
    let(:plan_2) { create(:plan, organization:, amount_cents: 99.99, pay_in_advance: true) }

    before do
      create(:charge, {
        plan: plan_2,
        billable_metric:,
        invoiceable:,
        pay_in_advance:,
        prorated: true,
        properties: {amount: '60', grouped_by:}
      })
    end

    it 'performs subscription upgrade and billing correctly' do
      travel_to(creation_time) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan.code
            # billing_time: 'calendar'
          }
        )
        perform_billing
      end

      # travel_to(creation_time + 4.days) do
      # send_event! "user_1"
      # send_event! "user_2"
      # end

      travel_to(upgrade_time) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan_2.code
            # billing_time: 'anniversary'
          }
        )

        # expect(customer.subscriptions.order(created_at: :asc).first).to be_terminated
        # expect(customer.invoices.count).to eq(2)
        # new_subscription = customer.subscriptions.order(created_at: :asc).last
        # expect(new_subscription.plan.code).to eq(plan_2.code)
        # expect(new_subscription).to be_active

        pp Fee.where(invoice_id: nil)
        # expect(Fee.where(invoice_id: nil, created_at: ...upgrade_time).count).to eq 2
        # expect(Fee.where(invoice_id: nil, created_at: upgrade_time..).count).to eq 0
      end

      # travel_to(upgrade_time + 4.days) do
      # #send_event! "user_3"
      # #send_event! "user_4"
      # end

      # travel_to(DateTime.new(2024, 7, 1, 0, 10)) do
      #   perform_billing
      #   pp Fee.where(invoice_id: nil).count
      #   expect(Fee.where(invoice_id: nil, created_at: Time.current.beginning_of_month..).count).to eq 4
      # end
    end
  end
end
