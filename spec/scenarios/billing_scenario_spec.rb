# frozen_string_literal: true

require 'rails_helper'

describe 'Billing Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }

  context 'when plan is billed monthly and subscription is calendar in an American timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'America/Bogota') }
    let(:plan) { create(:plan, organization:, amount_cents: 1000, interval: 'monthly') }

    it 'creates only one invoice on billing day' do
      ### 1st of Feb: Create a subscription
      feb1 = DateTime.new(2023, 2, 1)

      travel_to(feb1) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'calendar',
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 1st of Mar 00:00 UTC - 31 Feb 19:00 America/Bogota
      mar100 = DateTime.new(2023, 3, 1, 0, 0)
      travel_to(mar100) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.invoices.count).to be_zero

      ### 1st of Mar 05:00 UTC - 1st of Mar 00:00 America/Bogota
      mar105 = DateTime.new(2023, 3, 1, 5, 0)
      travel_to(mar105) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 1st of Mar 06:00 UTC - 1st of Mar 01:00 America/Bogota
      mar106 = DateTime.new(2023, 3, 1, 6, 0)
      travel_to(mar106) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 2nd of Mar 00:00 UTC - 1st of Mar 19:00 America/Bogota
      mar200 = DateTime.new(2023, 3, 2, 0, 0)
      travel_to(mar200) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)
    end
  end

  context 'when plan is billed monthly and subscription is calendar in an Asian timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'Asia/Kolkata') }
    let(:plan) { create(:plan, organization:, amount_cents: 1000, interval: 'monthly') }

    it 'creates only one invoice on billing day' do
      ### 1st of Feb: Create a subscription
      feb1 = DateTime.new(2023, 2, 1)

      travel_to(feb1) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'calendar',
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 28 of Feb 18:00 UTC - 28 Feb 23:30 Asia/Kolkata
      feb2818 = DateTime.new(2023, 2, 28, 18, 0)
      travel_to(feb2818) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.invoices.count).to be_zero

      ### 28 of Feb 19:00 UTC - 1st of Mar 00:30 Asia/Kolkata
      feb2819 = DateTime.new(2023, 2, 28, 19, 0)
      travel_to(feb2819) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 1st of Mar 00:00 UTC - 1st of Mar 05:30 Asia/Kolkata
      mar100 = DateTime.new(2023, 3, 1, 0, 0)
      travel_to(mar100) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 1st of Mar 18:00 UTC - 1st of Mar 23:30 Asia/Kolkata
      mar118 = DateTime.new(2023, 2, 1, 18, 0)
      travel_to(mar118) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 1st of Mar 19:00 UTC - 2nd of Mar 00:30 Asia/Kolkata
      mar119 = DateTime.new(2023, 2, 1, 19, 0)
      travel_to(mar119) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)
    end
  end

  context 'when plan is billed monthly and subscription is anniversary in an American timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'America/Bogota') }
    let(:plan) { create(:plan, organization:, amount_cents: 1000, interval: 'monthly') }

    it 'creates only one invoice on billing day' do
      ### 2nd of Feb: Create a subscription
      feb2 = DateTime.new(2023, 2, 2, 5)

      travel_to(feb2) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'anniversary',
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 31th of Feb 23:00 UTC - 1st of Mar 19:00 America/Bogota
      feb3123 = DateTime.new(2023, 2, 28, 23, 0)
      travel_to(feb3123) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.invoices.count).to be_zero

      ### 2nd of Mar 06:00 UTC - 2nd of Mar 01:00 America/Bogota
      mar206 = DateTime.new(2023, 3, 2, 6, 0)
      travel_to(mar206) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 2nd of Mar 07:00 UTC - 2nd of Mar 02:00 America/Bogota
      mar207 = DateTime.new(2023, 3, 2, 6, 0)
      travel_to(mar207) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 3rd of Mar 00:00 UTC - 2nd of Mar 19:00 America/Bogota
      mar300 = DateTime.new(2023, 3, 3, 0, 0)
      travel_to(mar300) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)
    end
  end

  context 'when plan is billed monthly and subscription is anniversary in an Asian timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'Asia/Kolkata') }
    let(:plan) { create(:plan, organization:, amount_cents: 1000, interval: 'monthly') }

    it 'creates only one invoice on billing day' do
      ### 1st of Feb: Create a subscription
      feb2 = DateTime.new(2023, 2, 2)

      travel_to(feb2) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: 'anniversary',
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 1st of Mar 18:00 UTC - 1st of Mar 23:30 Asia/Kolkata
      mar118 = DateTime.new(2023, 3, 1, 18, 0)
      travel_to(mar118) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.invoices.count).to be_zero

      ### 1st of Mar 19:00 UTC - 2nd of Mar 00:30 Asia/Kolkata
      mar119 = DateTime.new(2023, 3, 1, 19, 0)
      travel_to(mar119) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to be_zero

      ### 2nd of Mar 00:00 UTC - 2nd of Mar 05:30 Asia/Kolkata
      mar200 = DateTime.new(2023, 3, 2, 0, 0)
      travel_to(mar200) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 2nd of Mar 18:00 UTC - 2nd of Mar 23:30 Asia/Kolkata
      mar218 = DateTime.new(2023, 2, 2, 18, 0)
      travel_to(mar218) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)

      ### 2nd of Mar 19:00 UTC - 3rd of Mar 00:30 Asia/Kolkata
      mar219 = DateTime.new(2023, 2, 1, 19, 0)
      travel_to(mar219) do
        BillingService.new.call
      end

      perform_all_enqueued_jobs
      expect(subscription.reload.invoices.count).to eq(1)
    end
  end
end
