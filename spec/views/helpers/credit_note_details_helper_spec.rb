# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNoteDetailsHelper do
  describe "#rows" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:credit_note) { create(:credit_note, organization:, customer:, invoice:) }

    context "when the invoice is a credit invoice" do
      let(:invoice) { create(:invoice, :credit, organization:, customer:) }

      it "returns no rows" do
        expect(described_class.new(credit_note).rows).to eq([])
      end
    end

    context "with a contract product fee" do
      let(:contract) { create(:contract, organization:, customer:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
      let(:product_filter) do
        create(:product_filter, organization:, product: contract_rate_card.rate_card.product, invoice_display_name: "Region")
      end
      let(:fee) do
        create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
          invoiceable: contract_rate_card.rate_card.product, product_filter:, invoice_display_name: "Usage",
          amount_cents: 1250, precise_amount_cents: 1250, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
      end
      let(:credit_amount_cents) { 500 }
      let(:credit_true_up) { true }
      let(:credit_parent) { true }

      before do
        if credit_parent
          create(:credit_note_item, credit_note:, fee:, amount_cents: credit_amount_cents, precise_amount_cents: credit_amount_cents)
        end
      end

      it "returns a billed product row for only the credited amount" do
        rows = described_class.new(credit_note).rows

        expect(rows).to contain_exactly(
          described_class::Row.new(label: "Usage • Region", tax_rates: ["0.0%"],
            formatted_amount: MoneyHelper.format(5.to_money("EUR")), label_width: nil)
        )
      end

      context "with a credited product true-up" do
        let(:parent_fee_amount_cents) { 3000 }
        let(:child_fee_amount_cents) { 7000 }
        let(:credit_amount_cents) { parent_fee_amount_cents }
        let(:fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
            invoiceable: contract_rate_card.rate_card.product, product_filter:,
            invoice_display_name: "Usage", amount_cents: parent_fee_amount_cents, precise_amount_cents: parent_fee_amount_cents,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end
        let(:true_up_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
            invoiceable: contract_rate_card.rate_card.product, true_up_parent_fee: fee,
            invoice_display_name: "Usage true-up", amount_cents: child_fee_amount_cents, precise_amount_cents: child_fee_amount_cents,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end

        before do
          if credit_true_up
            create(:credit_note_item, credit_note:, fee: true_up_fee, amount_cents: child_fee_amount_cents,
              precise_amount_cents: child_fee_amount_cents)
          end
        end

        it "shows the credited parent followed by its credited child" do
          expect(described_class.new(credit_note).rows.map { |row| [row.label, row.formatted_amount] }).to eq([
            ["Usage • Region", MoneyHelper.format(30.to_money("EUR"))],
            [I18n.t("invoice.true_up_metric", metric: "Usage true-up"), MoneyHelper.format(70.to_money("EUR"))]
          ])
        end

        context "when the parent is unfiltered" do
          let(:product_filter) { nil }
          let(:parent_fee_amount_cents) { 6000 }
          let(:child_fee_amount_cents) { 4000 }

          it "shows the credited parent followed by its credited child" do
            expect(described_class.new(credit_note).rows.map { |row| [row.label, row.formatted_amount] }).to eq([
              ["Usage", MoneyHelper.format(60.to_money("EUR"))],
              [I18n.t("invoice.true_up_metric", metric: "Usage true-up"), MoneyHelper.format(40.to_money("EUR"))]
            ])
          end
        end

        context "when the child is not credited" do
          let(:credit_true_up) { false }

          it "does not display the child" do
            expect(described_class.new(credit_note).rows.map(&:label)).to eq(["Usage • Region"])
          end
        end
      end

      context "when only a product true-up child is credited" do
        let(:credit_parent) { false }
        let(:true_up_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
            invoiceable: contract_rate_card.rate_card.product, true_up_parent_fee: fee,
            invoice_display_name: "Standalone true-up", amount_cents: 400, precise_amount_cents: 400,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end

        before do
          create(:credit_note_item, credit_note:, fee: true_up_fee, amount_cents: 400, precise_amount_cents: 400)
        end

        it "renders it as a standalone product row" do
          expect(described_class.new(credit_note).rows.map(&:label)).to eq(["Standalone true-up"])
        end
      end

      context "when a standalone product true-up shares a rate card with another product" do
        let(:standalone_parent_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
            invoiceable: contract_rate_card.rate_card.product, invoice_display_name: "Uncredited parent",
            amount_cents: 300, precise_amount_cents: 300, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end
        let(:standalone_child_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
            invoiceable: contract_rate_card.rate_card.product, true_up_parent_fee: standalone_parent_fee,
            invoice_display_name: "Standalone child", amount_cents: 200, precise_amount_cents: 200,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end

        before do
          create(:credit_note_item, credit_note:, fee: standalone_child_fee, amount_cents: 200, precise_amount_cents: 200)
        end

        it "keeps both the unrelated product and standalone child visible" do
          expect(described_class.new(credit_note).rows.map { |row| [row.label, row.formatted_amount] }).to eq([
            ["Usage • Region", MoneyHelper.format(5.to_money("EUR"))],
            ["Standalone child", MoneyHelper.format(2.to_money("EUR"))]
          ])
        end
      end

      it "returns a display-ready contract section from the product loader" do
        expect(CreditNoteDetailsHelper::ContractRows.load(credit_note).sole).to be_a(CreditNoteItem)
        expect(CreditNoteDetailsHelper::SubscriptionRows.load(credit_note)).to be_empty
      end

      context "with multiple credited fees on contract rate cards" do
        let(:second_invoiceable) { contract_rate_card.rate_card.product }
        let(:second_contract_rate_card) { contract_rate_card }
        let(:second_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:,
            contract_rate_card: second_contract_rate_card,
            invoiceable: second_invoiceable, product_filter: second_product_filter,
            invoice_display_name: "Second usage", amount_cents: 1000, precise_amount_cents: 1000,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end
        let(:second_product_filter) do
          create(:product_filter, organization:, product: contract_rate_card.rate_card.product, invoice_display_name: "EU")
        end
        let(:second_credit_amount_cents) { 300 }

        before do
          create(:credit_note_item, credit_note:, fee: second_fee, amount_cents: second_credit_amount_cents,
            precise_amount_cents: second_credit_amount_cents)
        end

        context "when neither fee is filtered" do
          let(:product_filter) { nil }
          let(:second_product_filter) { nil }

          it "emits each fee as an aggregate-style row" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage", "Second usage"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq(["60%", "60%"])
          end

          context "with credited true-up children" do
            let(:credit_amount_cents) { 8000 }
            let(:second_credit_amount_cents) { 10_500 }
            let(:fee) do
              create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
                invoiceable: contract_rate_card.rate_card.product, product_filter:, invoice_display_name: "Usage",
                amount_cents: 8000, precise_amount_cents: 8000, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
            end
            let(:second_fee) do
              create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
                invoiceable: second_invoiceable, product_filter: second_product_filter,
                invoice_display_name: "Second usage", amount_cents: 10_500, precise_amount_cents: 10_500,
                taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
            end
            let(:first_true_up_fee) do
              create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
                invoiceable: contract_rate_card.rate_card.product, true_up_parent_fee: fee,
                invoice_display_name: "Usage true-up", amount_cents: 8000, precise_amount_cents: 8000,
                taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
            end
            let(:second_true_up_fee) do
              create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card:,
                invoiceable: contract_rate_card.rate_card.product, true_up_parent_fee: second_fee,
                invoice_display_name: "Second usage true-up", amount_cents: 3500, precise_amount_cents: 3500,
                taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
            end

            before do
              create(:credit_note_item, credit_note:, fee: first_true_up_fee, amount_cents: 8000, precise_amount_cents: 8000)
              create(:credit_note_item, credit_note:, fee: second_true_up_fee, amount_cents: 3500, precise_amount_cents: 3500)
            end

            it "shows both billed segments and their credited true-ups" do
              rows = described_class.new(credit_note).rows

              expect(rows.map(&:label)).to eq([
                "Usage", "Second usage",
                I18n.t("invoice.true_up_metric", metric: "Usage true-up"),
                I18n.t("invoice.true_up_metric", metric: "Second usage true-up")
              ])
              expect(rows.map(&:formatted_amount)).to eq([
                MoneyHelper.format(80.to_money("EUR")), MoneyHelper.format(105.to_money("EUR")),
                MoneyHelper.format(80.to_money("EUR")), MoneyHelper.format(35.to_money("EUR"))
              ])
            end
          end
        end

        context "when the same product is on different rate cards" do
          let(:product_filter) { nil }
          let(:second_product_filter) { nil }
          let(:second_rate_card) do
            create(:rate_card, organization:, product: contract_rate_card.rate_card.product)
          end
          let(:second_contract_rate_card) do
            create(:contract_rate_card, organization:, contract:, rate_card: second_rate_card)
          end

          it "keeps each rate-card group visible" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage", "Second usage"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq(["60%", "60%"])
          end
        end

        context "when every fee is filtered" do
          let(:second_invoiceable) { create(:product, organization:) }

          it "emits a separately labeled row for each credited fee" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage • Region", "Second usage • EU"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq([nil, nil])
          end
        end

        context "when multiple fees have distinct filters" do
          it "emits a separately labeled row for each credited fee" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage • Region", "Second usage • EU"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq([nil, nil])
          end
        end

        context "when multiple fees share a product filter" do
          let(:second_product_filter) { product_filter }

          it "emits a separate row for each fee in first-seen order" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage • Region", "Second usage • Region"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq([nil, nil])
          end
        end

        context "when only one fee is filtered" do
          let(:second_product_filter) { nil }

          it "displays both fees without filter suffixes" do
            rows = described_class.new(credit_note).rows

            expect(rows.map(&:label)).to eq(["Usage", "Second usage"])
            expect(rows.map(&:formatted_amount)).to eq([
              MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(3.to_money("EUR"))
            ])
            expect(rows.map(&:label_width)).to eq(["60%", "60%"])
          end
        end
      end

      context "when product identity or contract differs" do
        let(:different_product_rate_card) { create(:contract_rate_card, organization:, contract:) }
        let(:other_contract) { create(:contract, organization:, customer:) }
        let(:other_rate_card) { create(:contract_rate_card, organization:, contract: other_contract) }
        let(:second_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract: other_contract,
            contract_rate_card: other_rate_card, invoiceable: other_rate_card.rate_card.product,
            invoice_display_name: "Other contract",
            amount_cents: 500, precise_amount_cents: 500, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end
        let(:third_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:,
            contract_rate_card: different_product_rate_card,
            invoiceable: different_product_rate_card.rate_card.product, invoice_display_name: "Different product",
            amount_cents: 500, precise_amount_cents: 500, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end

        before do
          create(:credit_note_item, credit_note:, fee: second_fee, amount_cents: 200, precise_amount_cents: 200)
          create(:credit_note_item, credit_note:, fee: third_fee, amount_cents: 100, precise_amount_cents: 100)
        end

        it "keeps rows from different products and contracts separate" do
          rows = described_class.new(credit_note).rows

          expect(rows.map(&:label)).to eq(["Usage • Region", "Other contract", "Different product"])
          expect(rows.map(&:formatted_amount)).to eq([
            MoneyHelper.format(5.to_money("EUR")), MoneyHelper.format(2.to_money("EUR")),
            MoneyHelper.format(1.to_money("EUR"))
          ])
        end
      end

      context "when the fee has no billed display name" do
        let(:fee) { super().tap { |record| record.update!(invoice_display_name: nil) } }

        it "falls back to the product name" do
          expect(described_class.new(credit_note).rows.sole.label).to eq("#{fee.invoiceable.invoice_name} • Region")
        end
      end

      context "with a subscription fee on the same credit note" do
        let(:plan) { create(:plan, organization:) }
        let(:subscription) { create(:subscription, customer:, plan:) }
        let(:subscription_fee) do
          create(:fee, invoice:, subscription:, fee_type: :subscription, amount_cents: 1000, precise_amount_cents: 1000)
        end

        before do
          create(:credit_note_item, credit_note:, fee: subscription_fee, amount_cents: 200, precise_amount_cents: 200)
        end

        it "orchestrates contract rows before subscription rows from independent loaders", :bullet do
          expect(CreditNoteDetailsHelper::ContractRows.load(credit_note).sole.fee).to eq(fee)
          expect(CreditNoteDetailsHelper::SubscriptionRows.load(credit_note).sole.fee).to eq(subscription_fee)
          expect(described_class.new(credit_note).rows.map(&:label)).to eq([
            "Usage • Region", "#{I18n.t("credit_note.subscription")} - #{subscription.invoice_name}"
          ])
        end
      end

      context "when resolving fee taxes to the sole note tax of the same code" do
        let(:tax) { create(:tax, organization:, code: "vat", rate: 20) }

        before do
          create(:fee_applied_tax, fee:, tax:, tax_code: "vat", tax_rate: 10)
          create(:credit_note_applied_tax, credit_note:, tax:, tax_code: "vat", tax_rate: 20)
        end

        it "uses the sole note tax for that code" do
          expect(described_class.new(credit_note).rows.sole.tax_rates).to eq(["20.0%"])
        end
      end

      context "with multiple product taxes" do
        let(:second_product) { create(:product, organization:) }
        let(:second_contract_rate_card) do
          create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product: second_product))
        end
        let(:second_fee) do
          create(:fee, invoice:, subscription: nil, fee_type: :product, contract:, contract_rate_card: second_contract_rate_card,
            invoiceable: second_product, invoice_display_name: "Other usage",
            amount_cents: 1000, precise_amount_cents: 1000, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
        end
        let(:first_tax) { create(:tax, organization:, code: "first-vat", rate: 10) }
        let(:second_tax) { create(:tax, organization:, code: "second-vat", rate: 20) }

        before do
          create(:credit_note_item, credit_note:, fee: second_fee, amount_cents: 400, precise_amount_cents: 400)
          create(:fee_applied_tax, fee:, tax: first_tax, tax_code: "first-vat", tax_rate: 10)
          create(:fee_applied_tax, fee: second_fee, tax: second_tax, tax_code: "second-vat", tax_rate: 20)
          create(:credit_note_applied_tax, credit_note:, tax: first_tax, tax_code: "first-vat", tax_rate: 10)
          create(:credit_note_applied_tax, credit_note:, tax: second_tax, tax_code: "second-vat", tax_rate: 20)
        end

        it "maps each credited fee to its exact tax code and rate" do
          rows_by_label = described_class.new(credit_note).rows.index_by(&:label)

          expect(rows_by_label.fetch("Usage • Region").tax_rates).to eq(["10.0%"])
          expect(rows_by_label.fetch("Other usage").tax_rates).to eq(["20.0%"])
        end
      end
    end

    context "with subscription and add-on fees" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, customer:, plan:) }
      let(:subscription_fee) do
        create(:fee, invoice:, subscription:, fee_type: :subscription, amount_cents: 1000, precise_amount_cents: 1000)
      end
      let(:add_on) { create(:add_on, organization:) }
      let(:add_on_fee) do
        create(:one_off_fee, invoice:, add_on:, amount_cents: 500, precise_amount_cents: 500, invoice_display_name: "Setup")
      end

      let(:items_in_creation_order) { [[subscription_fee, 250], [add_on_fee, 125]] }

      before do
        items_in_creation_order.each_with_index do |(fee, amount_cents), index|
          create(:credit_note_item, credit_note:, fee:, amount_cents:, precise_amount_cents: amount_cents,
            created_at: Time.current + index.seconds)
        end
      end

      it "keeps subscription and add-on rows in the legacy order with partial amounts" do
        rows = described_class.new(credit_note).rows

        expect(rows.map(&:label)).to eq([
          "#{I18n.t("credit_note.subscription")} - #{subscription.invoice_name}",
          "Setup"
        ])
        expect(rows.map(&:formatted_amount)).to eq([
          MoneyHelper.format(2.5.to_money("EUR")), MoneyHelper.format(1.25.to_money("EUR"))
        ])
        expect(rows.first.label_width).to eq("60%")
        expect(rows.last.label_width).to be_nil
      end

      context "when the add-on is the first credited item" do
        let(:items_in_creation_order) { [[add_on_fee, 125], [subscription_fee, 250]] }

        it "renders the add-on bucket before later subscription buckets" do
          expect(described_class.new(credit_note).rows.map(&:label)).to eq([
            "Setup",
            "#{I18n.t("credit_note.subscription")} - #{subscription.invoice_name}"
          ])
        end
      end

      context "when only an add-on true-up child is credited" do
        let(:true_up_add_on_fee) do
          create(:one_off_fee, invoice:, add_on:, true_up_parent_fee: add_on_fee,
            amount_cents: 200, precise_amount_cents: 200, invoice_display_name: "Setup adjustment")
        end
        let(:items_in_creation_order) { [[true_up_add_on_fee, 100]] }

        it "renders the child in item order using the parent fee label without a width override" do
          row = described_class.new(credit_note).rows.sole

          expect(row.label).to eq(I18n.t("invoice.true_up_metric", metric: add_on_fee.invoice_name))
          expect(row.label_width).to be_nil
        end
      end
    end

    context "with filtered subscription charges" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, customer:, plan:) }
      let(:charge) { create(:standard_charge, organization:) }
      let(:charge_filter) do
        create(:charge_filter, charge:, invoice_display_name: "US")
      end
      let(:fee) do
        create(:charge_fee, invoice:, subscription:, charge:, charge_filter:, amount_cents: 500,
          precise_amount_cents: 500)
      end

      before do
        create(:credit_note_item, credit_note:, fee:, amount_cents: 125, precise_amount_cents: 125)
      end

      it "separates the fee name and filter display without duplicating separators" do
        row = described_class.new(credit_note).rows.sole

        expect(row.label).to eq("#{fee.invoice_name} • US")
        expect(row.label).not_to include("•  •")
        expect(row.formatted_amount).to eq(MoneyHelper.format(1.25.to_money("EUR")))
      end
    end

    context "with credited true-ups for multiple fees of one charge" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, customer:, plan:) }
      let(:charge) { create(:standard_charge, organization:) }
      let(:filtered) { false }
      let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "US") }
      let(:parent_fees) do
        %w[First Second].map do |name|
          create(:charge_fee, invoice:, subscription:, charge:, charge_filter: (charge_filter if filtered),
            invoice_display_name: name, amount_cents: 500, precise_amount_cents: 500)
        end
      end
      let(:true_up_fees) do
        parent_fees.map do |fee|
          create(:charge_fee, invoice:, subscription:, charge:, true_up_parent_fee: fee,
            invoice_display_name: "True-up #{fee.invoice_display_name}", amount_cents: 100, precise_amount_cents: 100)
        end
      end

      before do
        (parent_fees + true_up_fees).each do |fee|
          create(:credit_note_item, credit_note:, fee:, amount_cents: 50, precise_amount_cents: 50)
        end
      end

      context "when all fees are filtered" do
        let(:filtered) { true }

        it "shows each displayed parent and its credited true-up once" do
          labels = described_class.new(credit_note).rows.map(&:label)

          expect(labels).to eq([
            "First • US",
            "Second • US",
            I18n.t("invoice.true_up_metric", metric: "True-up First"),
            I18n.t("invoice.true_up_metric", metric: "True-up Second")
          ])
        end
      end

      context "when the charge group is unfiltered" do
        it "shows only the first parent and that parent's credited true-up" do
          labels = described_class.new(credit_note).rows.map(&:label)

          expect(labels).to eq([
            "First",
            I18n.t("invoice.true_up_metric", metric: "True-up First")
          ])
        end
      end

      context "with two charge groups" do
        let(:second_charge) { create(:standard_charge, organization:) }
        let(:second_parent) do
          create(:charge_fee, invoice:, subscription:, charge: second_charge, invoice_display_name: "Group B",
            amount_cents: 500, precise_amount_cents: 500)
        end
        let(:second_true_up) do
          create(:charge_fee, invoice:, subscription:, charge: second_charge, true_up_parent_fee: second_parent,
            invoice_display_name: "True-up B", amount_cents: 100, precise_amount_cents: 100)
        end

        before do
          create(:credit_note_item, credit_note:, fee: second_parent, amount_cents: 50, precise_amount_cents: 50)
          create(:credit_note_item, credit_note:, fee: second_true_up, amount_cents: 50, precise_amount_cents: 50)
        end

        it "renders each charge group's true-up before the next group" do
          expect(described_class.new(credit_note).rows.map(&:label)).to eq([
            "First",
            I18n.t("invoice.true_up_metric", metric: "True-up First"),
            "Group B",
            I18n.t("invoice.true_up_metric", metric: "True-up B")
          ])
        end
      end
    end
  end

  describe ".metered_source_id" do
    it "returns the source ID for product and charge fees only" do
      product_fee = build_stubbed(:fee, fee_type: :product, contract_rate_card_id: "00000000-0000-0000-0000-000000000001")
      charge_fee = build_stubbed(:fee, fee_type: :charge, charge_id: "00000000-0000-0000-0000-000000000002")
      add_on_fee = build_stubbed(:fee, fee_type: :add_on, charge_id: "00000000-0000-0000-0000-000000000003")

      expect([described_class.metered_source_id(product_fee), described_class.metered_source_id(charge_fee),
        described_class.metered_source_id(add_on_fee)]).to eq([product_fee.contract_rate_card_id, charge_fee.charge_id, nil])
    end
  end

  describe ".metered_filter_id" do
    it "returns the corresponding filter ID only for product and charge fees" do
      product_fee = build_stubbed(:fee, fee_type: :product, product_filter_id: "00000000-0000-0000-0000-000000000004")
      charge_fee = build_stubbed(:fee, fee_type: :charge, charge_filter_id: "00000000-0000-0000-0000-000000000005")
      add_on_fee = build_stubbed(:fee, fee_type: :add_on, product_filter_id: "00000000-0000-0000-0000-000000000006")

      expect([described_class.metered_filter_id(product_fee), described_class.metered_filter_id(charge_fee),
        described_class.metered_filter_id(add_on_fee)]).to eq([product_fee.product_filter_id, charge_fee.charge_filter_id, nil])
    end
  end

  describe ".credit_note_metered_group_key" do
    it "uses the rate card or charge as the source and includes fee type" do
      product_fee = build_stubbed(:fee, fee_type: :product, contract_rate_card_id: "00000000-0000-0000-0000-000000000001")
      charge_fee = build_stubbed(:fee, fee_type: :charge, charge_id: "00000000-0000-0000-0000-000000000002")

      expect(described_class.credit_note_metered_group_key(product_fee)).to eq(["product", product_fee.contract_rate_card_id])
      expect(described_class.credit_note_metered_group_key(charge_fee)).to eq(["charge", charge_fee.charge_id])
    end

    it "uses item keys for fees without a source and product true-ups" do
      uncarded_product = build_stubbed(:fee, fee_type: :product, contract_rate_card_id: nil)
      standalone_true_up = build_stubbed(:fee, fee_type: :product, contract_rate_card_id: "00000000-0000-0000-0000-000000000001",
        true_up_parent_fee_id: "00000000-0000-0000-0000-000000000007")
      unpersisted_charge = build(:fee, fee_type: :charge, charge_id: nil)

      expect(described_class.credit_note_metered_group_key(uncarded_product)).to eq(["product", uncarded_product.item_key])
      expect(described_class.credit_note_metered_group_key(standalone_true_up)).to eq(
        ["product", [:standalone_true_up, standalone_true_up.item_key]]
      )
      expect(described_class.credit_note_metered_group_key(unpersisted_charge)).to eq(["charge", unpersisted_charge.item_key])
    end
  end
end
