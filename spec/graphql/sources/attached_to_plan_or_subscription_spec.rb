# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::AttachedToPlanOrSubscription do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    context "when grouped by product" do
      subject(:source) { described_class.new(:product) }

      it "flags products carded on a plan or a subscription" do
        plan_attached = create(:product, organization:)
        create(:plan_rate_card, organization:, rate_card: create(:rate_card, organization:, product: plan_attached))

        subscription_attached = create(:product, organization:)
        create(:contract_rate_card, organization:, rate_card: create(:rate_card, organization:, product: subscription_attached))

        result = source.fetch([plan_attached.id, subscription_attached.id, product.id])

        expect(result).to eq([true, true, false])
      end

      it "ignores discarded rate cards" do
        create(:plan_rate_card, organization:, rate_card: create(:rate_card, organization:, product:)).rate_card.discard!

        expect(source.fetch([product.id])).to eq([false])
      end
    end

    context "when grouped by rate_card" do
      subject(:source) { described_class.new(:rate_card) }

      it "flags cards attached to a plan or a subscription" do
        plan_attached = create(:rate_card, organization:, product:)
        create(:plan_rate_card, organization:, rate_card: plan_attached)

        subscription_attached = create(:rate_card, organization:, product:)
        create(:contract_rate_card, organization:, rate_card: subscription_attached)

        free_card = create(:rate_card, organization:, product:)

        result = source.fetch([plan_attached.id, subscription_attached.id, free_card.id])

        expect(result).to eq([true, true, false])
      end
    end

    context "when grouped by product_category" do
      subject(:source) { described_class.new(:product_category) }

      it "flags categories through their products' cards" do
        attached_category = create(:product_category, organization:)
        carded_product = create(:product, organization:, product_category: attached_category)
        create(:plan_rate_card, organization:, rate_card: create(:rate_card, organization:, product: carded_product))

        empty_category = create(:product_category, organization:)

        result = source.fetch([attached_category.id, empty_category.id])

        expect(result).to eq([true, false])
      end
    end
  end
end
