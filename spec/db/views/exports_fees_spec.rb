# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_fees view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }

  let(:finalized_invoice) { create(:invoice, status: :finalized, organization:, customer:) }
  let(:deleted_invoice) { create(:invoice, status: :deleted, organization:, customer:) }

  let!(:finalized_fee) { create(:fee, invoice: finalized_invoice, subscription:, organization:) }
  let!(:deleted_fee) { create(:fee, invoice: deleted_invoice, subscription:, organization:) }
  # Recurring non-invoiceable fees are persisted with no invoice; the LEFT JOIN must keep them.
  let!(:invoiceless_fee) { create(:fee, invoice: nil, subscription:, organization:) }

  let(:exported_fee_ids) do
    ActiveRecord::Base.connection.select_values("SELECT lago_id FROM exports_fees")
  end

  it "excludes fees on deleted invoices while keeping finalized and invoice-less fees" do
    expect(exported_fee_ids).to include(finalized_fee.id, invoiceless_fee.id)
    expect(exported_fee_ids).not_to include(deleted_fee.id)
  end

  describe "fixed-charge fees" do
    # Fee::FEE_TYPES gained fixed_charge at index 5, but every CASE f.fee_type in
    # the view stopped at 4, so fixed-charge fees fell through to the subscription
    # ELSE branch: they were exported with the plan's code, name and description,
    # item_type 'subscription', lago_item_id set to the subscription, and type
    # resolving to the literal 'unknown'.
    let(:add_on) do
      create(:add_on, organization:, code: "byos", name: "BYOS", description: "Bring your own storage")
    end
    let(:fixed_charge) do
      create(
        :fixed_charge,
        organization:,
        plan: subscription.plan,
        add_on:,
        invoice_display_name: "Storage add-on"
      )
    end
    # subscription is set so the plans join resolves. Without it the old ELSE
    # branch returned NULL rather than the plan, which would hide the defect.
    let!(:fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice: finalized_invoice,
        organization:,
        subscription:,
        fixed_charge:,
        invoice_display_name: nil
      )
    end

    # Read the item JSON through ->> so the assertions do not depend on how the
    # adapter casts a json column.
    def item_for(id)
      ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT item->>'type' AS type,
               item->>'code' AS code,
               item->>'name' AS name,
               item->>'description' AS description,
               item->>'item_type' AS item_type,
               item->>'lago_item_id' AS lago_item_id,
               item->>'invoice_display_name' AS invoice_display_name
        FROM exports_fees
        WHERE lago_id = #{ActiveRecord::Base.connection.quote(id)}
      SQL
    end

    def row_for(id)
      ActiveRecord::Base.connection.select_one(
        "SELECT * FROM exports_fees WHERE lago_id = #{ActiveRecord::Base.connection.quote(id)}"
      )
    end

    it "serializes the add-on behind the fixed charge rather than the plan" do
      item = item_for(fixed_charge_fee.id)

      expect(item["type"]).to eq("fixed_charge")
      expect(item["item_type"]).to eq("add_on")
      expect(item["code"]).to eq(add_on.code)
      expect(item["name"]).to eq(add_on.name)
      expect(item["description"]).to eq(add_on.description)
      expect(item["lago_item_id"]).to eq(add_on.id)

      expect(item["code"]).not_to eq(subscription.plan.code)
      expect(item["lago_item_id"]).not_to eq(subscription.id)
    end

    it "exposes lago_fixed_charge_id and leaves lago_charge_id null" do
      row = row_for(fixed_charge_fee.id)

      expect(row["lago_fixed_charge_id"]).to eq(fixed_charge.id)
      expect(row["lago_charge_id"]).to be_nil
    end

    it "prefers the fixed charge's invoice_display_name over the add-on's" do
      expect(item_for(fixed_charge_fee.id)["invoice_display_name"]).to eq("Storage add-on")
    end

    it "reads the date boundaries from the fixed_charges_* properties" do
      row = row_for(fixed_charge_fee.id)

      expect(Time.zone.parse(row["from_date"]).to_date).to eq(Date.new(2022, 7, 1))
      expect(Time.zone.parse(row["to_date"]).to_date).to eq(Date.new(2022, 7, 31))
      # the generic from_datetime on the same fee is 2022-08-01
      expect(Time.zone.parse(row["from_date"]).to_date).not_to eq(Date.new(2022, 8, 1))
    end
  end
end
