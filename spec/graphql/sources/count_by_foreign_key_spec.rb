# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::CountByForeignKey do
  subject(:source) { described_class.new(ProductFilter, :product_id) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }

  describe "#fetch" do
    it "returns the count per id, zero when nothing matches" do
      create_pair(:product_filter, organization:, product:)
      empty_product = create(:product, organization:)

      result = source.fetch([product.id, empty_product.id])

      expect(result).to eq([2, 0])
    end

    it "does not count discarded rows" do
      kept = create(:product_filter, organization:, product:)
      create(:product_filter, organization:, product:).discard!

      result = source.fetch([product.id])

      expect(result).to eq([1])
      expect(product.filters).to eq([kept])
    end
  end
end
