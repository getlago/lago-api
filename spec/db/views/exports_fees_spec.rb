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

  it "excludes fees on deleted invoices while keeping finalized and invoice-less fees" do
    expect(exported_fee_ids).to include(finalized_fee.id, invoiceless_fee.id)
    expect(exported_fee_ids).not_to include(deleted_fee.id)
  end

  it "takes the customer of a subscription fee from its subscription and leaves the contract columns null" do
    row = ActiveRecord::Base.connection.select_one(
      "SELECT * FROM exports_fees WHERE lago_id = #{ActiveRecord::Base.connection.quote(finalized_fee.id)}"
    )

    expect(row["lago_customer_id"]).to eq(customer.id)
    expect(row.slice(
      "lago_contract_id",
      "lago_contract_rate_card_id",
      "lago_rate_card_rate_id",
      "lago_product_filter_id",
      "lago_product_id",
      "lago_rate_override_id"
    ).values).to all(be_nil)
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

  describe "product fees" do
    # Contract fees are billed from a rate card rate, without a subscription.
    let(:product) do
      create(:product, organization:, code: "storage", name: "Storage", description: "Object storage", invoice_display_name: nil)
    end
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:rate_card) { create(:rate_card, organization:, product:, product_filter:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:contract_invoice) { create(:invoice, status: :finalized, organization:, customer:) }
    let!(:product_fee) do
      create(
        :product_fee,
        invoice: contract_invoice,
        organization:,
        subscription: nil,
        contract:,
        contract_rate_card:,
        rate_card_rate:,
        product_filter:,
        invoice_display_name: nil
      )
    end

    it "serializes the product as the item" do
      expect(item_for(product_fee.id)).to eq(
        "type" => "product",
        "code" => "storage",
        "name" => "Storage",
        "description" => "Object storage",
        "item_type" => "product",
        "lago_item_id" => product.id,
        "invoice_display_name" => "Storage"
      )
    end

    it "prefers the product's invoice_display_name over its name" do
      product.update!(invoice_display_name: "Cloud storage")

      expect(item_for(product_fee.id)["invoice_display_name"]).to eq("Cloud storage")
    end

    ["", "  ", "\t\n"].each do |blank|
      it "falls back to the product's name when its invoice_display_name is #{blank.inspect}" do
        product.update!(invoice_display_name: blank)

        expect(item_for(product_fee.id)["invoice_display_name"]).to eq("Storage")
      end
    end

    it "keeps surrounding whitespace of a non-blank invoice_display_name" do
      product.update!(invoice_display_name: " Cloud storage ")

      expect(item_for(product_fee.id)["invoice_display_name"]).to eq(" Cloud storage ")
    end

    it "exposes the contract, rate card and product ids" do
      row = row_for(product_fee.id)

      expect(row.slice(
        "lago_contract_id",
        "lago_contract_rate_card_id",
        "lago_rate_card_rate_id",
        "lago_product_filter_id",
        "lago_product_id",
        "lago_subscription_id"
      )).to eq(
        "lago_contract_id" => contract.id,
        "lago_contract_rate_card_id" => contract_rate_card.id,
        "lago_rate_card_rate_id" => rate_card_rate.id,
        "lago_product_filter_id" => product_filter.id,
        "lago_product_id" => product.id,
        "lago_subscription_id" => nil
      )
    end

    context "when the fee is billed from a rate override" do
      let(:rate_override) { create(:rate_override, organization:) }
      let!(:product_fee) do
        create(
          :product_fee,
          invoice: contract_invoice,
          organization:,
          subscription: nil,
          contract:,
          contract_rate_card:,
          rate_card_rate:,
          rate_override:
        )
      end

      it "exposes lago_rate_override_id" do
        expect(row_for(product_fee.id)["lago_rate_override_id"]).to eq(rate_override.id)
      end
    end

    it "leaves lago_rate_override_id null when the fee has no rate override" do
      expect(row_for(product_fee.id)["lago_rate_override_id"]).to be_nil
    end

    it "takes the customer from the contract" do
      expect(row_for(product_fee.id)["lago_customer_id"]).to eq(customer.id)
    end

    it "takes invoiceable from the rate card's display_on_invoice" do
      expect(row_for(product_fee.id)["invoiceable"]).to be(true)
    end

    context "when the rate card is hidden from invoices" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, product_filter:, display_on_invoice: false) }

      it "exports the fee as not invoiceable" do
        expect(row_for(product_fee.id)["invoiceable"]).to be(false)
      end
    end

    context "when the catalog rows are deleted" do
      before do
        [rate_card_rate, rate_card, product_filter, product].each { |record| record.update!(deleted_at: Time.current) }
        contract_rate_card.update!(deleted_at: Time.current)
      end

      it "keeps the ids and the product item" do
        row = row_for(product_fee.id)

        expect(row["lago_product_id"]).to eq(product.id)
        expect(row["lago_rate_card_rate_id"]).to eq(rate_card_rate.id)
        expect(row["lago_contract_rate_card_id"]).to eq(contract_rate_card.id)
        expect(row["lago_product_filter_id"]).to eq(product_filter.id)
        expect(item_for(product_fee.id)["code"]).to eq("storage")
      end
    end
  end

  describe "credit purchase fees" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :pending, organization:, purchase_amount_cents: 8_000)
    end
    let(:purchase_invoice) { create(:invoice, :credit_purchase, status: :finalized, organization:, customer:) }
    let!(:purchase_fee) do
      create(
        :credit_purchase_fee,
        invoice: purchase_invoice,
        organization:,
        wallet_transaction:,
        invoice_display_name: nil
      )
    end

    it "serializes the wallet transaction as the item" do
      expect(item_for(purchase_fee.id)).to eq(
        "type" => "credit_purchase",
        "code" => "credit_purchase",
        "name" => "credit_purchase",
        "description" => "credit_purchase",
        "item_type" => "catalog_wallet_transaction",
        "lago_item_id" => wallet_transaction.id,
        "invoice_display_name" => "credit_purchase"
      )
    end

    it "leaves the customer and the contract null" do
      expect(row_for(purchase_fee.id).slice("lago_customer_id", "lago_contract_id")).to eq(
        "lago_customer_id" => nil,
        "lago_contract_id" => nil
      )
    end
  end
end
