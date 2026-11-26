# frozen_string_literal: true

require "rails_helper"

# Deferred triggers only fire on commit, so these examples cannot run inside a
# transaction that is rolled back.
RSpec.describe "record_deletion trigger", transaction: false do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:tax) { create(:tax, organization:) }

  it "is installed on every tracked table, deferred to commit" do
    installed = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_trigger AS t
      JOIN pg_class AS c ON c.oid = t.tgrelid
      WHERE t.tgname LIKE 'record_deletions_on_%'
        AND NOT t.tgisinternal
        AND t.tgdeferrable
        AND t.tginitdeferred
    SQL

    expect(installed).to match_array(RecordDeletion::TRACKED_TABLES)
  end

  describe "fees" do
    it "records the deleted row with its table, id and organization" do
      fee = create(:fee, invoice:, subscription:, organization:)

      fee.destroy!

      expect(RecordDeletion.find_by(record_id: fee.id)).to have_attributes(
        record_table: "fees",
        organization_id: organization.id
      )
    end

    it "stamps every timestamp as the transaction commits" do
      fee = create(:fee, invoice:, subscription:, organization:)
      transaction_started_at = nil

      ActiveRecord::Base.transaction do
        transaction_started_at = ActiveRecord::Base.connection.select_value("SELECT CURRENT_TIMESTAMP")
        fee.destroy!
      end

      tombstone = RecordDeletion.find_by!(record_id: fee.id)
      expect(tombstone.deleted_at).to be > transaction_started_at
      expect(tombstone.created_at).to eq(tombstone.deleted_at)
      expect(tombstone.updated_at).to eq(tombstone.deleted_at)
    end

    it "records one row per fee when several are deleted in a single statement" do
      fees = create_list(:fee, 3, invoice:, subscription:, organization:)

      Fee.where(id: fees.map(&:id)).delete_all

      expect(RecordDeletion.where(record_id: fees.map(&:id)).pluck(:record_id))
        .to match_array(fees.map(&:id))
    end
  end

  describe "fees_taxes" do
    it "records the deleted row" do
      fee = create(:fee, invoice:, subscription:, organization:)
      applied_tax = create(:fee_applied_tax, fee:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "fees_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "invoice_subscriptions" do
    it "records the deleted row" do
      invoice_subscription = create(:invoice_subscription, invoice:, subscription:, organization:)

      invoice_subscription.destroy!

      expect(RecordDeletion.find_by(record_id: invoice_subscription.id)).to have_attributes(
        record_table: "invoice_subscriptions",
        organization_id: organization.id
      )
    end
  end

  describe "invoices_taxes" do
    it "records the deleted row" do
      applied_tax = create(:invoice_applied_tax, invoice:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "invoices_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "credit_notes_taxes" do
    it "records the deleted row" do
      credit_note = create(:credit_note, invoice:, customer:, organization:)
      applied_tax = create(:credit_note_applied_tax, credit_note:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "credit_notes_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "billing_entities_taxes" do
    it "records the deleted row" do
      billing_entity = create(:billing_entity, organization:)
      applied_tax = create(:billing_entity_applied_tax, billing_entity:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "billing_entities_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "contract_rate_cards_terms" do
    it "records the deleted row" do
      term = create(:contract_rate_card_term, organization:)

      term.destroy!

      expect(RecordDeletion.find_by(record_id: term.id)).to have_attributes(
        record_table: "contract_rate_cards_terms",
        organization_id: organization.id
      )
    end
  end

  describe "customers_taxes" do
    it "records the deleted row" do
      applied_tax = create(:customer_applied_tax, customer:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "customers_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "rate_cards_taxes" do
    it "records the deleted row" do
      rate_card = create(:rate_card, organization:)
      applied_tax = create(:rate_card_applied_tax, rate_card:, tax:, organization:)

      applied_tax.destroy!

      expect(RecordDeletion.find_by(record_id: applied_tax.id)).to have_attributes(
        record_table: "rate_cards_taxes",
        organization_id: organization.id
      )
    end
  end

  describe "plans_taxes" do
    it "records the deleted rows of plans and catalog plans" do
      plan = create(:plan, organization:)
      applied_taxes = [
        create(:plan_applied_tax, plan:, tax:, organization:),
        create(:plan_applied_tax, :catalog_plan, tax:, organization:)
      ]

      applied_taxes.each(&:destroy!)

      expect(RecordDeletion.where(record_id: applied_taxes.map(&:id)).pluck(:record_table, :organization_id))
        .to eq([["plans_taxes", organization.id]] * 2)
    end
  end

  describe "a tax deletion" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:plan) { create(:plan, organization:) }

    it "records the applied taxes it removes from billing entities, customers, rate cards and plans" do
      applied_taxes = [
        create(:billing_entity_applied_tax, billing_entity:, tax:, organization:),
        create(:customer_applied_tax, customer:, tax:, organization:),
        create(:rate_card_applied_tax, rate_card:, tax:, organization:),
        create(:plan_applied_tax, plan:, tax:, organization:),
        create(:plan_applied_tax, :catalog_plan, tax:, organization:)
      ]

      Taxes::DestroyService.call(tax:).raise_if_error!

      expect(RecordDeletion.where(record_id: applied_taxes.map(&:id)).pluck(:record_id, :record_table))
        .to match_array([
          [applied_taxes[0].id, "billing_entities_taxes"],
          [applied_taxes[1].id, "customers_taxes"],
          [applied_taxes[2].id, "rate_cards_taxes"],
          [applied_taxes[3].id, "plans_taxes"],
          [applied_taxes[4].id, "plans_taxes"]
        ])
    end
  end

  describe "a contract rate card units update" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, units: 2) }

    it "records the terms it replaces" do
      replaced_term = contract_rate_card.terms.sole

      ContractRateCards::UpdateService.call(contract_rate_card:, params: {units: 5}).raise_if_error!

      expect(RecordDeletion.where(record_id: replaced_term.id).pick(:record_table)).to eq("contract_rate_cards_terms")
      expect(contract_rate_card.terms.reload.sole.units).to eq(5)
    end
  end

  describe "a draft invoice refresh" do
    let(:started_at) { 1.month.ago.beginning_of_month }

    let(:draft_invoice) { create(:invoice, :draft, organization:, customer:) }

    let(:subscription) do
      create(
        :subscription,
        customer:,
        organization:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end

    let(:invoice_subscription) do
      create(:invoice_subscription, invoice: draft_invoice, subscription:, recurring: true)
    end

    let(:fee) { create(:fee, invoice: draft_invoice, subscription:, organization:) }

    before do
      create(:tax, :applied_to_billing_entity, organization:, rate: 15)
      invoice_subscription
      fee
    end

    it "records the rows the refresh replaces" do
      Invoices::RefreshDraftService.call(invoice: draft_invoice).raise_if_error!

      expect(RecordDeletion.where(record_id: fee.id).pick(:record_table)).to eq("fees")
      expect(RecordDeletion.where(record_id: invoice_subscription.id).pick(:record_table))
        .to eq("invoice_subscriptions")
    end
  end

  describe "two transactions deleting concurrently" do
    it "stamps the late committer after the tombstone that committed before it" do
      slow_fee = create(:fee, invoice:, subscription:, organization:)
      fast_fee = create(:fee, invoice:, subscription:, organization:)

      pool = ActiveRecord::Base.connection_pool
      slow = pool.checkout
      fast = pool.checkout

      begin
        slow.execute("BEGIN")
        slow.execute("DELETE FROM fees WHERE id = #{slow.quote(slow_fee.id)}")

        fast.execute("BEGIN")
        fast.execute("DELETE FROM fees WHERE id = #{fast.quote(fast_fee.id)}")
        fast.execute("COMMIT")

        expect(RecordDeletion.where(record_id: slow_fee.id)).to be_empty
        cursor = RecordDeletion.find_by!(record_id: fast_fee.id).updated_at

        slow.execute("COMMIT")

        expect(RecordDeletion.find_by!(record_id: slow_fee.id).updated_at).to be > cursor
      ensure
        pool.checkin(slow)
        pool.checkin(fast)
      end
    end
  end

  it "does not record anything when the deleting transaction rolls back" do
    fee = create(:fee, invoice:, subscription:, organization:)

    ActiveRecord::Base.transaction do
      fee.destroy!
      raise ActiveRecord::Rollback
    end

    expect(RecordDeletion.where(record_id: fee.id)).to be_empty
  end
end
