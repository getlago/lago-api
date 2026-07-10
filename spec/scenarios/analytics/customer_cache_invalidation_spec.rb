# frozen_string_literal: true

require "rails_helper"

describe "Analytics customer cache invalidation" do
  include GraphQLHelper

  let(:membership) { create(:membership, organization:) }
  let(:organization) { create(:organization, created_at: 3.months.ago, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billing_entity) { organization.default_billing_entity }

  let(:overdue_balances_query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String, $months: Int, $expireCache: Boolean) {
        overdueBalances(currency: $currency, externalCustomerId: $externalCustomerId, months: $months, expireCache: $expireCache) {
          collection {
            amountCents
            currency
            lagoInvoiceIds
            month
          }
        }
      }
    GQL
  end

  let(:gross_revenues_query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String, $months: Int, $expireCache: Boolean) {
        grossRevenues(currency: $currency, externalCustomerId: $externalCustomerId, months: $months, expireCache: $expireCache) {
          collection {
            month
            amountCents
            currency
            invoicesCount
          }
        }
      }
    GQL
  end

  # Freeze the clock to midday of the current day so the wall-clock version
  # token and the Date.current embedded in the cache key stay stable: the
  # nested `travel 1.second` around expiring reads can no longer cross a day
  # boundary. Midday of today (not a hardcoded date) is used on purpose: the
  # analytics SQL groups on Postgres CURRENT_DATE, which travel_to does not
  # freeze, so the frozen Ruby clock must remain in the real current month.
  # A non-block travel_to is used so the per-example `travel 1.second do` blocks
  # don't trip ActiveSupport's nested-block guard.
  before { travel_to(Time.current.midday) }
  after { travel_back }

  def overdue_amounts(**variables)
    collection = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "analytics:view",
      query: overdue_balances_query,
      variables:
    )["data"]["overdueBalances"]["collection"]
    collection.sum { |row| row["amountCents"].to_i }
  end

  def gross_amounts(**variables)
    collection = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: "analytics:view",
      query: gross_revenues_query,
      variables:
    )["data"]["grossRevenues"]["collection"]
    collection.sum { |row| row["amountCents"].to_i }
  end

  describe "overdue balances family invalidation", cache: :redis do
    before do
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: Time.current,
        issuing_date: Time.current, total_amount_cents: 50, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 70, currency: "USD", billing_entity:)
    end

    it "invalidates every cached variant of the customer when one variant expires" do
      # Each read populates an independent cache entry under the current token.
      # months: 1 keeps only the current month, so it differs from the unfiltered read.
      expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(150)
      expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(70)
      expect(overdue_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(50)

      # The mutation moves every variant: EUR (past + current month), USD, and
      # the current-month-only window, so each post-expiry sibling read changes
      # value and a cache hit is distinguishable from a recompute.
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 130, currency: "USD", billing_entity:)
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: Time.current,
        issuing_date: Time.current, total_amount_cents: 50, currency: "EUR", billing_entity:)

      # Without expireCache every variant still serves the original cached value.
      expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(150)
      expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(70)
      expect(overdue_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(50)

      travel 1.second do
        # A single expiring read on one variant bumps the per-customer token.
        expect(overdue_amounts(externalCustomerId: customer.external_id, expireCache: true)).to eq(700)

        # Every other variant now recomputes too, proving the whole family was invalidated.
        expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(500)
        expect(overdue_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(200)
        expect(overdue_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(100)
      end
    end

    it "leaves org-level cached entries untouched after a customer expiry" do
      # The org-level read (no externalCustomerId) uses the unversioned cache key.
      expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(overdue_amounts).to eq(220)

      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)

      travel 1.second do
        expect(overdue_amounts(externalCustomerId: customer.external_id, expireCache: true)).to eq(520)

        # The org-level entry was not versioned, so it still serves the stale value.
        expect(overdue_amounts).to eq(220)
      end
    end
  end

  describe "gross revenues family invalidation", cache: :redis do
    before do
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: Time.current,
        issuing_date: Time.current, total_amount_cents: 50, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 70, currency: "USD", billing_entity:)
    end

    it "invalidates every cached variant of the customer when one variant expires" do
      expect(gross_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(gross_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(150)
      expect(gross_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(70)
      expect(gross_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(50)

      # Mutation moves EUR, USD and the current-month window so every sibling
      # variant changes and a cache hit is distinguishable from a recompute.
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 130, currency: "USD", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: Time.current,
        issuing_date: Time.current, total_amount_cents: 50, currency: "EUR", billing_entity:)

      expect(gross_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(gross_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(150)
      expect(gross_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(70)
      expect(gross_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(50)

      travel 1.second do
        expect(gross_amounts(externalCustomerId: customer.external_id, expireCache: true)).to eq(700)

        expect(gross_amounts(externalCustomerId: customer.external_id, currency: "EUR")).to eq(500)
        expect(gross_amounts(externalCustomerId: customer.external_id, currency: "USD")).to eq(200)
        expect(gross_amounts(externalCustomerId: customer.external_id, months: 1)).to eq(100)
      end
    end

    it "leaves org-level cached entries untouched after a customer expiry" do
      expect(gross_amounts(externalCustomerId: customer.external_id)).to eq(220)
      expect(gross_amounts).to eq(220)

      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)

      travel 1.second do
        expect(gross_amounts(externalCustomerId: customer.external_id, expireCache: true)).to eq(520)

        expect(gross_amounts).to eq(220)
      end
    end
  end

  describe "per-customer isolation", cache: :redis do
    let(:other_customer) { create(:customer, organization:) }

    before do
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
      create(:invoice, customer: other_customer, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 70, currency: "EUR", billing_entity:)
    end

    it "does not invalidate another customer's cached entry when one customer expires" do
      # Each customer's read populates an entry under its own per-customer token.
      expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(100)
      expect(overdue_amounts(externalCustomerId: other_customer.external_id)).to eq(70)

      # Both customers get new overdue invoices, so a recompute is distinguishable
      # from a cache hit for either of them.
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)
      create(:invoice, customer: other_customer, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 130, currency: "EUR", billing_entity:)

      travel 1.second do
        # Expiring customer A bumps only customer A's token.
        expect(overdue_amounts(externalCustomerId: customer.external_id, expireCache: true)).to eq(400)

        # Customer B's token is untouched, so its entry still serves the stale value.
        expect(overdue_amounts(externalCustomerId: other_customer.external_id)).to eq(70)
      end
    end
  end

  describe "org-level expireCache is a no-op", cache: :redis do
    before do
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
    end

    it "leaves a customer-scoped cached entry untouched when expireCache runs without externalCustomerId" do
      # Cache the customer-scoped entry under its per-customer token.
      expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(100)

      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)

      travel 1.second do
        # The Base guard only expires when external_customer_id is present, so an
        # org-level expireCache read cannot bump any per-customer token.
        expect(overdue_amounts(expireCache: true)).to eq(400)

        # The customer-scoped entry still serves its stale value.
        expect(overdue_amounts(externalCustomerId: customer.external_id)).to eq(100)
      end
    end
  end

  describe "cross-model isolation", cache: :redis do
    before do
      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
      # Draft so it counts toward overdue balance but not gross revenue (status = 1).
      create(:invoice, customer:, organization:, status: :draft, payment_overdue: true, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
    end

    it "does not invalidate gross revenue when overdue balance is expired for the same customer" do
      expect(gross_amounts(externalCustomerId: customer.external_id)).to eq(100)

      create(:invoice, customer:, organization:, status: :finalized, payment_due_date: 1.month.ago,
        issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)

      travel 1.second do
        # Expiring the overdue balance token must not touch the gross revenue token.
        Analytics::OverdueBalance.find_all_by(organization.id, external_customer_id: customer.external_id, expire_cache: true)

        expect(gross_amounts(externalCustomerId: customer.external_id)).to eq(100)
      end
    end
  end

  # InvoiceCollectionsResolver does not expose externalCustomerId or expireCache
  # (and is premium-gated), so the per-customer versioning is unreachable through
  # GraphQL. This model is exercised at the model level via .find_all_by instead.
  describe "invoice collections family invalidation", cache: :redis do
    def collection_amounts(**args)
      Analytics::InvoiceCollection
        .find_all_by(organization.id, **args)
        .sum { |row| row["amount_cents"] }
    end

    before do
      create(:invoice, customer:, organization:, status: :finalized, payment_status: :succeeded,
        payment_due_date: 1.month.ago, issuing_date: 1.month.ago, total_amount_cents: 100, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_status: :pending,
        payment_due_date: 1.month.ago, issuing_date: 1.month.ago, total_amount_cents: 50, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_status: :failed,
        payment_due_date: 1.month.ago, issuing_date: 1.month.ago, total_amount_cents: 70, currency: "USD", billing_entity:)
    end

    it "invalidates every cached variant of the customer when one variant expires" do
      expect(collection_amounts(external_customer_id: customer.external_id)).to eq(220)
      expect(collection_amounts(external_customer_id: customer.external_id, currency: "EUR")).to eq(150)
      expect(collection_amounts(external_customer_id: customer.external_id, currency: "USD")).to eq(70)

      # Mutation moves both EUR and USD so each sibling variant changes and a
      # cache hit is distinguishable from a recompute.
      create(:invoice, customer:, organization:, status: :finalized, payment_status: :succeeded,
        payment_due_date: 1.month.ago, issuing_date: 1.month.ago, total_amount_cents: 300, currency: "EUR", billing_entity:)
      create(:invoice, customer:, organization:, status: :finalized, payment_status: :failed,
        payment_due_date: 1.month.ago, issuing_date: 1.month.ago, total_amount_cents: 130, currency: "USD", billing_entity:)

      expect(collection_amounts(external_customer_id: customer.external_id)).to eq(220)
      expect(collection_amounts(external_customer_id: customer.external_id, currency: "EUR")).to eq(150)
      expect(collection_amounts(external_customer_id: customer.external_id, currency: "USD")).to eq(70)

      travel 1.second do
        expect(collection_amounts(external_customer_id: customer.external_id, expire_cache: true)).to eq(650)

        expect(collection_amounts(external_customer_id: customer.external_id, currency: "EUR")).to eq(450)
        expect(collection_amounts(external_customer_id: customer.external_id, currency: "USD")).to eq(200)
      end
    end
  end
end
