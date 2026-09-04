# frozen_string_literal: true

require "rails_helper"

RSpec.describe "record_deletion trigger" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:tax) { create(:tax, organization:) }

  it "is installed on every tracked table" do
    installed = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_trigger AS t
      JOIN pg_class AS c ON c.oid = t.tgrelid
      WHERE t.tgname LIKE 'record_deletions_on_%'
        AND NOT t.tgisinternal
    SQL

    expect(installed).to match_array(RecordDeletion::TRACKED_TABLES)
  end

  describe "fees" do
    it "records the deleted row with its table, id and organization" do
      fee = create(:fee, invoice:, subscription:, organization:)

      expect { fee.destroy! }.to change(RecordDeletion, :count).by(1)

      expect(RecordDeletion.sole).to have_attributes(
        record_table: "fees",
        record_id: fee.id,
        organization_id: organization.id
      )
    end

    it "stamps every timestamp from the delete rather than from the transaction" do
      fee = create(:fee, invoice:, subscription:, organization:)
      transaction_started_at = ActiveRecord::Base.connection.select_value("SELECT CURRENT_TIMESTAMP")

      fee.destroy!

      tombstone = RecordDeletion.sole
      expect(tombstone.deleted_at).to be > transaction_started_at
      expect(tombstone.created_at).to eq(tombstone.deleted_at)
      expect(tombstone.updated_at).to eq(tombstone.deleted_at)
    end

    it "records one row per fee when several are deleted in a single statement" do
      fees = create_list(:fee, 3, invoice:, subscription:, organization:)

      expect { Fee.where(id: fees.map(&:id)).delete_all }
        .to change(RecordDeletion, :count).by(3)

      expect(RecordDeletion.pluck(:record_id)).to match_array(fees.map(&:id))
    end
  end

  describe "fees_taxes" do
    it "records the deleted row" do
      fee = create(:fee, invoice:, subscription:, organization:)
      applied_tax = create(:fee_applied_tax, fee:, tax:, organization:)

      expect { applied_tax.destroy! }.to change(RecordDeletion, :count).by(1)

      expect(RecordDeletion.sole).to have_attributes(
        record_table: "fees_taxes",
        record_id: applied_tax.id,
        organization_id: organization.id
      )
    end
  end

  describe "invoice_subscriptions" do
    it "records the deleted row" do
      invoice_subscription = create(:invoice_subscription, invoice:, subscription:, organization:)

      expect { invoice_subscription.destroy! }.to change(RecordDeletion, :count).by(1)

      expect(RecordDeletion.sole).to have_attributes(
        record_table: "invoice_subscriptions",
        record_id: invoice_subscription.id,
        organization_id: organization.id
      )
    end
  end

  describe "invoices_taxes" do
    it "records the deleted row" do
      applied_tax = create(:invoice_applied_tax, invoice:, tax:, organization:)

      expect { applied_tax.destroy! }.to change(RecordDeletion, :count).by(1)

      expect(RecordDeletion.sole).to have_attributes(
        record_table: "invoices_taxes",
        record_id: applied_tax.id,
        organization_id: organization.id
      )
    end
  end

  describe "credit_notes_taxes" do
    it "records the deleted row" do
      credit_note = create(:credit_note, invoice:, customer:, organization:)
      applied_tax = create(:credit_note_applied_tax, credit_note:, tax:, organization:)

      expect { applied_tax.destroy! }.to change(RecordDeletion, :count).by(1)

      expect(RecordDeletion.sole).to have_attributes(
        record_table: "credit_notes_taxes",
        record_id: applied_tax.id,
        organization_id: organization.id
      )
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

      expect(RecordDeletion.where(record_table: "fees").pluck(:record_id)).to include(fee.id)
      expect(RecordDeletion.where(record_table: "invoice_subscriptions").pluck(:record_id))
        .to include(invoice_subscription.id)
    end
  end

  it "does not record anything when the deleting transaction rolls back" do
    fee = create(:fee, invoice:, subscription:, organization:)

    expect do
      ActiveRecord::Base.transaction do
        fee.destroy!
        raise ActiveRecord::Rollback
      end
    end.not_to change(RecordDeletion, :count)
  end
end
