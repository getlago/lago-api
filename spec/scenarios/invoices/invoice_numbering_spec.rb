# frozen_string_literal: true

require "rails_helper"

describe "Invoice Numbering Scenario", :scenarios, type: :request, transaction: false do
  let(:customer_first) { create(:customer, organization:, billing_entity: billing_entity_first) }
  let(:customer_second) { create(:customer, organization:, billing_entity: billing_entity_first) }
  let(:customer_third) { create(:customer, organization:, billing_entity: billing_entity_first) }
  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }

  let(:organization) do
    create(
      :organization,
      webhook_url: nil,
      document_numbering: "per_customer",
      timezone: "Europe/Paris",
      email_settings: []
    )
  end

  let(:billing_entity_first) { organization.default_billing_entity }

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 12_900,
      pay_in_advance: true
    )
  end
  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 100_000,
      pay_in_advance: true
    )
  end

  before do
    organization.default_billing_entity.update(timezone: "Europe/Paris")
    organization.webhook_endpoints.destroy_all
    organization.update!(document_number_prefix: "ORG-1")
  end

  it "creates invoice numbers correctly" do
    # NOTE: Jul 19th: create the subscription
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer_first.external_id,
          external_id: customer_first.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )
      create_subscription(
        {
          external_customer_id: customer_second.external_id,
          external_id: customer_second.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )
      create_subscription(
        {
          external_customer_id: customer_third.external_id,
          external_id: customer_third.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([1, 1, 1])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
      expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001])
    end

    # NOTE: August 19th: Bill subscription
    travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([2, 2, 2])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
      expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002])
    end

    # NOTE: September 19th: Bill subscription
    travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([3, 3, 3])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
      expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003])
    end

    # NOTE: October 19th: Switching to per_organization numbering and Bill subscription
    travel_to(DateTime.new(2023, 10, 19, 12, 12)) do
      update_organization(document_numbering: "per_organization", document_number_prefix: "ORG-11")

      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([4, 4, 4])
      expect(organization_sequential_ids).to match_array([10, 11, 12])
      expect(billing_entity_sequential_ids).to match_array([10, 11, 12])
      expect(numbers).to match_array(%w[ORG-11-202310-010 ORG-11-202310-011 ORG-11-202310-012])
    end

    # NOTE: November 19th: Switching to per_customer numbering and Bill subscription
    travel_to(DateTime.new(2023, 11, 19, 12, 12)) do
      update_organization(document_numbering: "per_customer")

      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([5, 5, 5])
      expect(organization_sequential_ids).to match_array([0, 0, 0])
      expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
      expect(numbers).to match_array(%w[ORG-11-001-005 ORG-11-002-005 ORG-11-003-005])
    end

    # NOTE: November 22: New subscription for second customer
    time = DateTime.new(2023, 11, 22, 12, 12)
    travel_to(time) do
      create_subscription(
        {
          external_customer_id: customer_second.external_id,
          external_id: "new_external_id",
          plan_code: yearly_plan.code,
          billing_time: "anniversary",
          subscription_at: time.iso8601
        }
      )

      invoices = organization.reload.invoices.order(created_at: :desc)

      expect(invoices.first.sequential_id).to eq(6)
      expect(invoices.first.organization_sequential_id).to be_zero
      expect(invoices.first.billing_entity_sequential_id).to be_nil
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
          ]
        )
    end

    # NOTE: December 19th: Switching to per_organization numbering and Bill subscription
    travel_to(DateTime.new(2023, 12, 19, 12, 12)) do
      update_organization(document_numbering: "per_organization")

      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([6, 6, 7])
      expect(organization_sequential_ids).to match_array([17, 18, 19])
      expect(billing_entity_sequential_ids).to match_array([17, 18, 19])
      expect(numbers).to match_array(%w[ORG-11-202312-017 ORG-11-202312-018 ORG-11-202312-019])
    end

    # NOTE: January 19th 2024: Billing subscription
    travel_to(DateTime.new(2024, 1, 19, 12, 12)) do
      perform_billing

      invoices = organization.invoices.order(created_at: :desc).limit(3)
      sequential_ids = invoices.pluck(:sequential_id)
      organization_sequential_ids = invoices.pluck(:organization_sequential_id)
      billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
      numbers = invoices.pluck(:number)

      expect(sequential_ids).to match_array([7, 7, 8])
      expect(organization_sequential_ids).to match_array([20, 21, 22])
      expect(billing_entity_sequential_ids).to match_array([20, 21, 22])
      expect(numbers).to match_array(%w[ORG-11-202401-020 ORG-11-202401-021 ORG-11-202401-022])
    end
  end

  context "with organization timezone" do
    it "creates invoice numbers correctly" do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: "calendar",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: "calendar",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: "calendar",
            subscription_at: subscription_at.iso8601
          }
        )

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, 1, 1])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001])
      end

      # NOTE: August 1st: Bill subscription
      travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([2, 2, 2])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002])
      end

      # NOTE: September 1st: Bill subscription
      travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([3, 3, 3])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003])
      end

      timezone = "Europe/Paris"
      customer_first.update(timezone:)
      customer_second.update(timezone:)
      customer_third.update(timezone:)

      # NOTE: October 1st: Switching to per_organization numbering and Bill subscription
      travel_to(DateTime.new(2023, 9, 30, 23, 10)) do
        update_organization(document_numbering: "per_organization", document_number_prefix: "ORG-11")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([4, 4, 4])
        expect(organization_sequential_ids).to match_array([10, 11, 12])
        expect(billing_entity_sequential_ids).to match_array([10, 11, 12])
        expect(numbers).to match_array(%w[ORG-11-202310-010 ORG-11-202310-011 ORG-11-202310-012])
      end
    end
  end

  context "with grace period and per_customer numbering" do
    let(:customer_second) { create(:customer, organization:, invoice_grace_period: 2) }

    it "creates invoice numbers correctly" do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, nil, 1])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-DRAFT ORG-1-003-001])
      end

      # NOTE: Jul 20th: New subscription for the first customer
      time = subscription_at + 1.day
      travel_to(time) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: "new_external_id",
            plan_code: yearly_plan.code,
            billing_time: "anniversary",
            subscription_at: time.iso8601
          }
        )

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.first.sequential_id).to eq(2)
        expect(invoices.first.organization_sequential_id).to be_zero
        expect(invoices.first.billing_entity_sequential_id).to be_nil
        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-DRAFT
              ORG-1-003-001
              ORG-1-001-002
            ]
          )
      end

      # NOTE: Jul 21st: New subscription for the second customer
      time = subscription_at + 2.days
      travel_to(time) do
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: "new_external_id_2",
            plan_code: yearly_plan.code,
            billing_time: "anniversary",
            subscription_at: time.iso8601
          }
        )

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.first.sequential_id).to be_nil
        expect(invoices.first.organization_sequential_id).to be_zero
        expect(invoices.first.billing_entity_sequential_id).to be_nil
        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-DRAFT
              ORG-1-003-001
              ORG-1-001-002
              ORG-1-DRAFT
            ]
          )
      end

      travel_to(time + 1.hour) do
        draft_invoice1 = customer_second.reload.invoices.draft.order(created_at: :asc).first

        finalize_invoice(draft_invoice1)

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-002-001
              ORG-1-003-001
              ORG-1-001-002
              ORG-1-DRAFT
            ]
          )
      end

      travel_to(time + 2.hours) do
        draft_invoice2 = customer_second.reload.invoices.draft.order(created_at: :asc).last

        finalize_invoice(draft_invoice2)

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-002-001
              ORG-1-003-001
              ORG-1-001-002
              ORG-1-002-002
            ]
          )
      end

      # NOTE: August 19th: Bill subscription
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = organization.reload.invoices.order(created_at: :desc).pluck(:number)

        expect(sequential_ids).to match_array([3, nil, 2])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers)
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-002-001
              ORG-1-003-001
              ORG-1-001-002
              ORG-1-002-002
              ORG-1-001-003
              ORG-1-DRAFT
              ORG-1-003-002
            ]
          )
      end

      # NOTE: September 19th: Bill subscription
      travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = organization.reload.invoices.order(created_at: :desc).pluck(:number)

        expect(sequential_ids).to match_array([4, nil, 3])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers)
          .to match_array(
            %w[
              ORG-1-001-001
              ORG-1-002-001
              ORG-1-003-001
              ORG-1-001-002
              ORG-1-002-002
              ORG-1-001-003
              ORG-1-DRAFT
              ORG-1-003-002
              ORG-1-001-004
              ORG-1-DRAFT
              ORG-1-003-003
            ]
          )
      end
    end
  end

  context "with grace period and per_organization numbering" do
    let(:customer_second) { create(:customer, organization:, invoice_grace_period: 2) }

    let(:organization) do
      create(
        :organization,
        webhook_url: nil,
        document_numbering: "per_organization",
        timezone: "Europe/Paris",
        email_settings: [],
        billing_entities: [billing_entity]
      )
    end

    let(:billing_entity) { create(:billing_entity, document_numbering: "per_billing_entity", timezone: "Europe/Paris",) }

    it "creates invoice numbers correctly" do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, nil, 1])
        expect(organization_sequential_ids).to match_array([1, 0, 2])
        expect(billing_entity_sequential_ids).to match_array([1, nil, 2])
        expect(numbers).to match_array(%w[ORG-1-202307-001 ORG-1-DRAFT ORG-1-202307-002])
      end

      # NOTE: Jul 20th: New subscription for the first customer
      time = subscription_at + 1.day
      travel_to(time) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: "new_external_id",
            plan_code: yearly_plan.code,
            billing_time: "anniversary",
            subscription_at: time.iso8601
          }
        )

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.first.sequential_id).to eq(2)
        expect(invoices.first.organization_sequential_id).to eq(3)
        expect(invoices.first.billing_entity_sequential_id).to eq(3)
        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-DRAFT
              ORG-1-202307-002
              ORG-1-202307-003
            ]
          )
      end

      # NOTE: Jul 21st: New subscription for the second customer
      time = subscription_at + 2.days
      travel_to(time) do
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: "new_external_id_2",
            plan_code: yearly_plan.code,
            billing_time: "anniversary",
            subscription_at: time.iso8601
          }
        )

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.first.sequential_id).to be_nil
        expect(invoices.first.organization_sequential_id).to be_zero
        expect(invoices.first.billing_entity_sequential_id).to be_nil
        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-DRAFT
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-DRAFT
            ]
          )
      end

      travel_to(time + 1.hour) do
        draft_invoice1 = customer_second.reload.invoices.draft.order(created_at: :asc).first

        finalize_invoice(draft_invoice1)

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-202307-004
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-DRAFT
            ]
          )
      end

      travel_to(time + 2.hours) do
        draft_invoice2 = customer_second.reload.invoices.draft.order(created_at: :asc).last

        finalize_invoice(draft_invoice2)

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-202307-004
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-202307-005
            ]
          )
      end

      # NOTE: August 19th: Bill subscription
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = organization.reload.invoices.order(created_at: :desc).pluck(:number)

        expect(sequential_ids).to match_array([3, nil, 2])
        expect(organization_sequential_ids).to match_array([6, 0, 7])
        expect(billing_entity_sequential_ids).to match_array([6, nil, 7])
        expect(numbers)
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-202307-004
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-202307-005
              ORG-1-202308-006
              ORG-1-DRAFT
              ORG-1-202308-007
            ]
          )
      end

      # NOTE: September 19th: Bill subscription
      travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = organization.reload.invoices.order(created_at: :desc).pluck(:number)

        expect(sequential_ids).to match_array([4, nil, 3])
        expect(organization_sequential_ids).to match_array([8, 0, 9])
        expect(billing_entity_sequential_ids).to match_array([8, nil, 9])
        expect(numbers)
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-202307-004
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-202307-005
              ORG-1-202308-006
              ORG-1-DRAFT
              ORG-1-202308-007
              ORG-1-202309-008
              ORG-1-DRAFT
              ORG-1-202309-009
            ]
          )
      end

      travel_to(DateTime.new(2023, 9, 20, 12, 12)) do
        draft_invoice1 = customer_second.reload.invoices.draft.order(created_at: :asc).first

        finalize_invoice(draft_invoice1)

        invoices = organization.reload.invoices.order(created_at: :desc)

        expect(invoices.pluck(:number))
          .to match_array(
            %w[
              ORG-1-202307-001
              ORG-1-202307-004
              ORG-1-202307-002
              ORG-1-202307-003
              ORG-1-202307-005
              ORG-1-202308-006
              ORG-1-202309-010
              ORG-1-202308-007
              ORG-1-202309-008
              ORG-1-DRAFT
              ORG-1-202309-009
            ]
          )
      end
    end
  end

  context "with partner customer" do
    let(:customer_third) { create(:customer, organization:, billing_entity: billing_entity_first, account_type: "partner") }

    around { |test| lago_premium!(&test) }

    before { organization.update!(premium_integrations: ["revenue_share"]) }

    it "creates invoice numbers correctly" do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, 1, 1])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001])
      end

      # NOTE: August 19th: Bill subscription
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([2, 2, 2])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002])
      end

      # NOTE: September 19th: Bill subscription
      travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([3, 3, 3])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003])
      end

      # NOTE: October 19th: Switching to per_organization numbering and Bill subscription
      travel_to(DateTime.new(2023, 10, 19, 12, 12)) do
        update_organization(document_numbering: "per_organization", document_number_prefix: "ORG-11")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([4, 4, 4])
        expect(organization_sequential_ids).to match_array([7, 8, 0])
        expect(billing_entity_sequential_ids).to match_array([7, 8, nil])
        expect(numbers).to match_array(%w[ORG-11-202310-007 ORG-11-202310-008 ORG-11-003-004])
      end

      # NOTE: November 19th: Switching to per_customer numbering and Bill subscription
      travel_to(DateTime.new(2023, 11, 19, 12, 12)) do
        update_organization(document_numbering: "per_customer")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([5, 5, 5])
        expect(organization_sequential_ids).to match_array([0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil])
        expect(numbers).to match_array(%w[ORG-11-001-005 ORG-11-002-005 ORG-11-003-005])
      end

      # NOTE: December 19th: Switching to per_organization numbering and Bill subscription
      travel_to(DateTime.new(2023, 12, 19, 12, 12)) do
        update_organization(document_numbering: "per_organization")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(3)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([6, 6, 6])
        expect(organization_sequential_ids).to match_array([11, 12, 0])
        expect(billing_entity_sequential_ids).to match_array([11, 12, nil])
        expect(numbers).to match_array(%w[ORG-11-202312-011 ORG-11-202312-012 ORG-11-003-006])
      end
    end
  end

  context "with multiple billing entities" do
    let(:organization) { create(:organization, billing_entities: [billing_entity_first, billing_entity_second]) }
    let(:billing_entity_first) { create(:billing_entity, document_numbering: "per_billing_entity") }
    let(:billing_entity_second) { create(:billing_entity, document_numbering: "per_billing_entity") }
    let(:customer_fourth) { create(:customer, organization:, billing_entity: billing_entity_second) }
    let(:customer_fifth) { create(:customer, organization:, billing_entity: billing_entity_second) }

    it "creates invoice numbers correctly" do
      # NOTE: Jul 19th: create the subscriptions
      travel_to(subscription_at) do
        # First billing entity customers
        create_subscription(
          {
            external_customer_id: customer_first.external_id,
            external_id: customer_first.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_second.external_id,
            external_id: customer_second.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_third.external_id,
            external_id: customer_third.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )

        # Second billing entity customers
        create_subscription(
          {
            external_customer_id: customer_fourth.external_id,
            external_id: customer_fourth.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )
        create_subscription(
          {
            external_customer_id: customer_fifth.external_id,
            external_id: customer_fifth.external_id,
            plan_code: monthly_plan.code,
            billing_time: "anniversary",
            subscription_at: subscription_at.iso8601
          }
        )

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([1, 1, 1, 1, 1])
        expect(organization_sequential_ids).to match_array([0, 0, 0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([1, 2, 3, 1, 2])
        expect(numbers).to match_array(%w[ORG-1-001-001 ORG-1-002-001 ORG-1-003-001 ORG-1-004-001 ORG-1-005-001])
      end

      # NOTE: August 19th: Bill subscriptions
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([2, 2, 2, 2, 2])
        expect(organization_sequential_ids).to match_array([0, 0, 0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([4, 5, 6, 3, 4])
        expect(numbers).to match_array(%w[ORG-1-001-002 ORG-1-002-002 ORG-1-003-002 ORG-1-004-002 ORG-1-005-002])
      end

      # NOTE: September 19th: Bill subscriptions
      travel_to(DateTime.new(2023, 9, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([3, 3, 3, 3, 3])
        expect(organization_sequential_ids).to match_array([0, 0, 0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([7, 8, 9, 5, 6])
        expect(numbers).to match_array(%w[ORG-1-001-003 ORG-1-002-003 ORG-1-003-003 ORG-1-004-003 ORG-1-005-003])
      end

      # NOTE: October 19th: Switching to per_organization numbering and Bill subscriptions
      travel_to(DateTime.new(2023, 10, 19, 12, 12)) do
        update_organization(document_numbering: "per_organization", document_number_prefix: "ORG-11")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([4, 4, 4, 4, 4])
        expect(organization_sequential_ids).to match_array([16, 17, 18, 19, 20])
        expect(billing_entity_sequential_ids).to match_array([10, 11, 12, 7, 8])
        expect(numbers).to match_array(%w[ORG-11-202310-016 ORG-11-202310-017 ORG-11-202310-018 ORG-11-202310-019 ORG-11-202310-020])
      end

      # NOTE: November 19th: Switching to per_customer numbering and Bill subscriptions
      travel_to(DateTime.new(2023, 11, 19, 12, 12)) do
        update_organization(document_numbering: "per_customer")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([5, 5, 5, 5, 5])
        expect(organization_sequential_ids).to match_array([0, 0, 0, 0, 0])
        expect(billing_entity_sequential_ids).to match_array([nil, nil, nil, 9, 10])
        expect(numbers).to match_array(%w[ORG-11-001-005 ORG-11-002-005 ORG-11-003-005 ORG-11-004-005 ORG-11-005-005])
      end

      # NOTE: December 19th: Switching to per_organization numbering and Bill subscriptions
      travel_to(DateTime.new(2023, 12, 19, 12, 12)) do
        update_organization(document_numbering: "per_organization")

        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([6, 6, 6, 6, 6])
        expect(organization_sequential_ids).to match_array([26, 27, 28, 29, 30])
        expect(billing_entity_sequential_ids).to match_array([16, 17, 18, 11, 12])
        expect(numbers).to match_array(%w[ORG-11-202312-026 ORG-11-202312-027 ORG-11-202312-028 ORG-11-202312-029 ORG-11-202312-030])
      end

      # NOTE: January 19th 2024: Billing subscriptions
      travel_to(DateTime.new(2024, 1, 19, 12, 12)) do
        perform_billing

        invoices = organization.invoices.order(created_at: :desc).limit(5)
        sequential_ids = invoices.pluck(:sequential_id)
        organization_sequential_ids = invoices.pluck(:organization_sequential_id)
        billing_entity_sequential_ids = invoices.pluck(:billing_entity_sequential_id)
        numbers = invoices.pluck(:number)

        expect(sequential_ids).to match_array([7, 7, 7, 7, 7])
        expect(organization_sequential_ids).to match_array([31, 32, 33, 34, 35])
        expect(billing_entity_sequential_ids).to match_array([19, 20, 21, 13, 14])
        expect(numbers).to match_array(%w[ORG-11-202401-031 ORG-11-202401-032 ORG-11-202401-033 ORG-11-202401-034 ORG-11-202401-035])
      end
    end
  end
end
