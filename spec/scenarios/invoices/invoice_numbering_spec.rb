# frozen_string_literal: true

require 'rails_helper'

describe 'Invoice Numbering Scenario', :scenarios, type: :request, transaction: false do
  let(:customer_first) { create(:customer, organization:) }
  let(:customer_second) { create(:customer, organization:) }
  let(:customer_third) { create(:customer, organization:) }
  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }

  let(:organization) do
    create(:organization, webhook_url: false, document_numbering: 'per_customer', timezone: 'Europe/Paris')
  end

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: 'monthly',
      amount_cents: 12_900,
      pay_in_advance: true,
    )
  end
  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: 'yearly',
      amount_cents: 100_000,
      pay_in_advance: true,
    )
  end

  before do
    organization.webhook_endpoints.destroy_all
    organization.update!(document_number_prefix: 'ORG-1')
  end

  it 'creates invoice numbers correctly' do
    # NOTE: Jul 19th: create the subscription
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer_first.external_id,
          external_id: customer_first.external_id,
          plan_code: monthly_plan.code,
          billing_time: 'anniversary',
          subscription_at: subscription_at.iso8601,
        },
      )
      create_subscription(
        {
          external_customer_id: customer_second.external_id,
          external_id: customer_second.external_id,
          plan_code: monthly_plan.code,
          billing_time: 'anniversary',
          subscription_at: subscription_at.iso8601,
        },
      )
      create_subscription(
        {
          external_customer_id: customer_third.external_id,
          external_id: customer_third.external_id,
          plan_code: monthly_plan.code,
          billing_time: 'anniversary',
          subscription_at: subscription_at.iso8601,
        },
      )

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([1, 1, 1])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001])
    end

    # NOTE: August 19th: Bill subscription
    travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([2, 2, 2])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002])
    end

    # NOTE: September 19th: Bill subscription
    travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([3, 3, 3])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003])
    end

    # NOTE: October 19th: Switching to per_organization numbering and Bill subscription
    travel_to(DateTime.new(2023, 10, 19, 12, 12)) do
      organization.update!(document_numbering: 'per_organization', document_number_prefix: 'ORG-11')

      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([4, 4, 4])
      expect(organization_sequential_ids).to match_array([10, 11, 12])
      expect(numbers).to match_array(%w[ORG-11-202310-010 ORG-11-202310-011 ORG-11-202310-012])
    end

    # NOTE: November 19th: Switching to per_customer numbering and Bill subscription
    travel_to(DateTime.new(2023, 11, 19, 12, 12)) do
      organization.update!(document_numbering: 'per_customer')

      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([5, 5, 5])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(numbers).to match_array(%w[ORG-11-001-005 ORG-11-002-005 ORG-11-003-005])
    end

    # NOTE: November 22: New subscription for second customer
    time = DateTime.new(2023, 11, 22, 12, 12)
    travel_to(time) do
      create_subscription(
        {
          external_customer_id: customer_second.external_id,
          external_id: 'new_external_id',
          plan_code: yearly_plan.code,
          billing_time: 'anniversary',
          subscription_at: time.iso8601,
        },
      )

      invoices = organization.reload.invoices.order(created_at: :desc)

      expect(invoices.first.sequential_id).to eq(6)
      expect(invoices.first.organization_sequential_id).to eq(0)
      expect(invoices.pluck(:number))
        .to match_array(
          %w[
            ORG-1-001-001
            ORG-1-002-001
            ORG-1-003-001
            ORG-1-001-002
            ORG-1-002-002
            ORG-1-003-002
            ORG-1-001-003
            ORG-1-002-003
            ORG-1-003-003
            ORG-11-202310-010
            ORG-11-202310-011
            ORG-11-202310-012
            ORG-11-001-005
            ORG-11-002-005
            ORG-11-003-005
            ORG-11-002-006
          ],
        )
    end

    # NOTE: December 19th: Switching to per_organization numbering and Bill subscription
    travel_to(DateTime.new(2023, 12, 19, 12, 12)) do
      organization.update!(document_numbering: 'per_organization')

      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([6, 6, 7])
      expect(organization_sequential_ids).to match_array([17, 18, 19])
      expect(numbers).to match_array(%w[ORG-11-202312-017 ORG-11-202312-018 ORG-11-202312-019])
    end

    # NOTE: January 19th 2024: Billing subscription
    travel_to(DateTime.new(2024, 1, 19, 12, 12)) do
      Subscriptions::BillingService.call
      perform_all_enqueued_jobs

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([7, 7, 8])
      expect(organization_sequential_ids).to match_array([20, 21, 22])
      expect(numbers).to match_array(%w[ORG-11-202401-020 ORG-11-202401-021 ORG-11-202401-022])
    end
  end

  context 'with organization timezone' do
    it 'creates invoice numbers correctly' do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: 'calendar',
            subscription_at: subscription_at.iso8601,
          },
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: 'calendar',
            subscription_at: subscription_at.iso8601,
          },
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: 'calendar',
            subscription_at: subscription_at.iso8601,
          },
        )

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, 1, 1])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001])
      end

      # NOTE: August 1st: Bill subscription
      travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
        Subscriptions::BillingService.call
        perform_all_enqueued_jobs

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([2, 2, 2])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002])
      end

      # NOTE: September 1st: Bill subscription
      travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
        Subscriptions::BillingService.call
        perform_all_enqueued_jobs

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([3, 3, 3])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003])
      end

      timezone = 'Europe/Paris'
      customer_first.update(timezone:)
      customer_second.update(timezone:)
      customer_third.update(timezone:)

      # NOTE: October 1st: Switching to per_organization numbering and Bill subscription
      travel_to(DateTime.new(2023, 9, 30, 23, 10)) do
        organization.update!(document_numbering: 'per_organization', document_number_prefix: 'ORG-11')

        Subscriptions::BillingService.call
        perform_all_enqueued_jobs

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([4, 4, 4])
        expect(organization_sequential_ids).to match_array([10, 11, 12])
        expect(numbers).to match_array(%w[ORG-11-202310-010 ORG-11-202310-011 ORG-11-202310-012])
      end
    end
  end
end
