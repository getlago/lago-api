# frozen_string_literal: true

require 'rails_helper'

describe 'Duplicate Invoices Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }

  context 'when customer timezone for weekly anniversary' do
    let(:customer) { create(:customer, organization:, timezone: 'Europe/Paris') }
    let(:plan) { create(:plan, interval: 'weekly', organization:, amount_cents: 1000) }

    it 'does not enqueue two billing jobs' do
      ### May 2: Create subscription + charge.
      travel_to(DateTime.new(2023, 5, 2)) do
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

      ### 23rd of May 20:00 UTC - 23rd of May 22:00 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 20, 0)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.to change { subscription.reload.invoices.count }.from(0).to(1)
      end

      ### 23rd of May 21:00 UTC - 23rd of May 23:00 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 21, 0)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end

      ### 23rd of May 22:59 UTC - 24th of May 00:59 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 22, 10)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end

      ### 24th of May 00:10 UTC - 24th of May 02:10 Europe/Paris
      travel_to(DateTime.new(2023, 5, 24, 0, 10)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end
    end
  end

  context 'when customer timezone for monthly anniversary' do
    let(:customer) { create(:customer, organization:, timezone: 'Europe/Paris') }
    let(:plan) { create(:plan, interval: 'monthly', organization:, amount_cents: 1000) }

    it 'does not enqueue two billing jobs' do
      ### May 2: Create subscription + charge.
      travel_to(DateTime.new(2023, 5, 2)) do
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

      ### 23rd of May 20:00 UTC - 23rd of May 22:00 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 20, 0)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.to change { subscription.reload.invoices.count }.from(0).to(1)
      end

      ### 23rd of May 21:00 UTC - 23rd of May 23:00 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 21, 0)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end

      ### 23rd of May 22:59 UTC - 24th of May 00:59 Europe/Paris
      travel_to(DateTime.new(2023, 5, 23, 22, 10)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end

      ### 24th of May 00:10 UTC - 24th of May 02:10 Europe/Paris
      travel_to(DateTime.new(2023, 5, 24, 0, 10)) do
        BillingService.new.call
        expect { perform_all_enqueued_jobs }.not_to change { subscription.reload.invoices.count }
      end
    end
  end
end