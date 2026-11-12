# frozen_string_literal: true

require "rails_helper"

describe CatalogWalletSelectors::ReplaceService do
  subject(:result) { described_class.call(wallet:, applies_to:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:product_category) { create(:product_category, organization:, code: "ai") }
  let_it_be(:product) { create(:product, organization:, product_category:, code: "api_calls") }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:, code: "premium_model") }

  let(:wallet) { create(:plan_wallet, organization:) }
  let(:applies_to) { {include: entries} }
  let(:entries) do
    [
      {type: "fee_type", code: "metered"},
      {type: "product_category", code: "ai"},
      {type: "product", code: "api_calls", with_product_filters: true},
      {type: "product_filters", product_code: "api_calls", code: "premium_model"}
    ]
  end

  def targets(selectors)
    selectors.map do |selector|
      selector.attributes.symbolize_keys
        .slice(:selector_type, :fee_type, :product_category_id, :product_id, :product_filter_id, :with_product_filters)
        .compact
    end
  end

  it "stores one selector per entry on the wallet" do
    expect(result).to be_success
    expect(targets(result.selectors)).to match_array([
      {selector_type: "fee_type", fee_type: "metered", with_product_filters: false},
      {selector_type: "product_category", product_category_id: product_category.id, with_product_filters: false},
      {selector_type: "product", product_id: product.id, with_product_filters: true},
      {selector_type: "product_filters", product_filter_id: product_filter.id, with_product_filters: false}
    ])
    expect(result.selectors.map { [it.organization_id, it.plan_wallet_id, it.catalog_wallet_id] }.uniq)
      .to eq([[organization.id, wallet.id, nil]])
  end

  context "when the wallet belongs to a contract" do
    let(:wallet) { create(:catalog_wallet, organization:) }
    let(:entries) { [{type: "fee_type", code: "fixed"}] }

    it "stores the selector on the contract wallet" do
      expect(result).to be_success
      expect(result.selectors.sole).to have_attributes(catalog_wallet_id: wallet.id, plan_wallet_id: nil, fee_type: "fixed")
    end
  end

  context "when the wallet does not exist" do
    let(:wallet) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
    end
  end

  context "when a product entry omits the filters flag" do
    let(:entries) { [{type: "product", code: "api_calls"}] }

    it "leaves the product's filters out" do
      expect(result.selectors.sole.with_product_filters).to be(false)
    end
  end

  context "when two entries name the same product" do
    let(:entries) { [{type: "product", code: "api_calls"}, {type: "product", code: "api_calls", with_product_filters: true}] }

    it "stores it once, with its filters" do
      expect(targets(result.selectors)).to eq([{selector_type: "product", product_id: product.id, with_product_filters: true}])
    end
  end

  context "when the wallet already has selectors" do
    let(:entries) { [{type: "fee_type", code: "metered"}, {type: "product", code: "api_calls"}] }
    let(:kept_selector) { create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet) }
    let(:changed_selector) do
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet,
        selector_type: "product", fee_type: nil, product:, with_product_filters: true)
    end
    let(:removed_selector) do
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet,
        selector_type: "product_category", fee_type: nil, product_category:)
    end

    before do
      kept_selector
      changed_selector
      removed_selector
    end

    it "keeps the matching ones, updates their flag and removes the others" do
      expect(result).to be_success
      expect(result.selectors.map(&:id)).to match_array([kept_selector.id, changed_selector.id])
      expect(changed_selector.reload.with_product_filters).to be(false)
      expect(CatalogWalletSelector.where(id: removed_selector.id)).to be_empty
    end

    context "when include is empty" do
      let(:entries) { [] }

      it "removes every selector" do
        expect(result).to be_success
        expect(wallet.selectors.reload).to be_empty
      end
    end

    context "when an entry is refused" do
      let(:entries) { [{type: "fee_type", code: "fixed"}, {type: "product", code: "unknown"}] }

      it "leaves the selectors as they were" do
        expect(result).not_to be_success
        expect(wallet.selectors.reload.map(&:id)).to match_array([kept_selector.id, changed_selector.id, removed_selector.id])
      end
    end
  end

  context "when applies_to is nil" do
    let(:applies_to) { nil }

    it "stores no selector" do
      expect(result).to be_success
      expect(result.selectors).to be_empty
    end
  end

  context "when exclude is supplied" do
    let(:applies_to) { {include: [], exclude: []} }

    it "refuses it" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq({"applies_to.exclude": ["not_supported"]})
    end
  end

  describe "refused entries" do
    [
      ["an unknown type", {type: "rate_card", code: "api_calls"}, :type, "value_is_invalid"],
      ["a missing code", {type: "product"}, :code, "value_is_mandatory"],
      ["a non scalar code", {type: "product", code: {a: 1}}, :code, "value_is_invalid"],
      ["an unknown fee type", {type: "fee_type", code: "usage"}, :code, "value_is_invalid"],
      ["an unknown product category", {type: "product_category", code: "unknown"}, :code, "product_category_not_found"],
      ["an unknown product", {type: "product", code: "unknown"}, :code, "product_not_found"],
      ["a non boolean filters flag", {type: "product", code: "api_calls", with_product_filters: "yes"}, :with_product_filters, "value_is_invalid"],
      ["a filters flag on another type", {type: "fee_type", code: "metered", with_product_filters: true}, :with_product_filters, "value_is_invalid"],
      ["a product filter without its product", {type: "product_filters", code: "premium_model"}, :product_code, "value_is_mandatory"],
      ["a product filter of an unknown product", {type: "product_filters", product_code: "unknown", code: "premium_model"}, :product_code, "product_not_found"],
      ["an unknown product filter", {type: "product_filters", product_code: "api_calls", code: "unknown"}, :code, "product_filter_not_found"]
    ].each do |description, entry, field, error_code|
      context "with #{description}" do
        let(:entries) { [{type: "fee_type", code: "metered"}, entry] }

        it "fails on that entry's #{field} and stores nothing" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq({"applies_to.include[1].#{field}": [error_code]})
          expect(wallet.selectors.reload).to be_empty
        end
      end
    end

    context "with a product of another organization" do
      let(:entries) { [{type: "product", code: create(:product, organization: create(:organization)).code}] }

      it "does not find it" do
        expect(result.error.messages).to eq({"applies_to.include[0].code": ["product_not_found"]})
      end
    end

    context "with an entry that is not an object" do
      let(:entries) { ["metered"] }

      it "fails on the entry" do
        expect(result.error.messages).to eq({"applies_to.include[0]": ["value_is_invalid"]})
      end
    end

    context "with an include that is not a list" do
      let(:applies_to) { {include: "metered"} }

      it "fails on include" do
        expect(result.error.messages).to eq({"applies_to.include": ["value_is_invalid"]})
      end
    end
  end
end
