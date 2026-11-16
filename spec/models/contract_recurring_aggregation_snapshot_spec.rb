# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRecurringAggregationSnapshot do
  subject(:snapshot) { build(:contract_recurring_aggregation_snapshot) }

  describe "associations" do
    it do
      expect(snapshot).to belong_to(:organization)
      expect(snapshot).to belong_to(:contract)
      expect(snapshot).to belong_to(:product)
      expect(snapshot).to belong_to(:product_filter).optional
      expect(snapshot).to belong_to(:billable_metric)
    end
  end

  describe "soft deleted associations" do
    let(:product) { create(:product) }
    let(:product_filter) { create(:product_filter, organization: product.organization, product:) }
    let(:snapshot) { create(:contract_recurring_aggregation_snapshot, organization: product.organization, product:, product_filter:) }

    before do
      snapshot
      product_filter.discard!
      product.discard!
    end

    it "still resolves a discarded product" do
      expect(described_class.find(snapshot.id).product).to eq(product)
    end

    it "still resolves a discarded product filter" do
      expect(described_class.find(snapshot.id).product_filter).to eq(product_filter)
    end
  end

  describe "validations" do
    it do
      expect(snapshot).to validate_presence_of(:to_datetime)
      expect(snapshot).to validate_presence_of(:watermark)
      expect(snapshot).to validate_numericality_of(:units)
    end
  end

  describe "unique index" do
    let(:product) { create(:product) }
    let(:existing) { create(:contract_recurring_aggregation_snapshot, organization: product.organization, product:, product_filter:, grouped_by:) }
    let(:product_filter) { nil }
    let(:grouped_by) { {} }
    let(:duplicate_to_datetime) { existing.to_datetime }
    let(:duplicate_contract) { existing.contract }
    let(:duplicate_product) { existing.product }
    let(:duplicate_product_filter) { existing.product_filter }
    let(:duplicate_grouped_by) { existing.grouped_by }
    let(:duplicate) do
      build(
        :contract_recurring_aggregation_snapshot,
        organization: existing.organization,
        contract: duplicate_contract,
        product: duplicate_product,
        product_filter: duplicate_product_filter,
        grouped_by: duplicate_grouped_by,
        to_datetime: duplicate_to_datetime
      )
    end

    context "without product filter" do
      it "rejects a second snapshot for the same period, treating NULL filters as equal" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with grouped_by" do
      let(:grouped_by) { {"region" => "eu"} }

      it "rejects a second snapshot for the same group" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a product filter" do
      let(:product_filter) { create(:product_filter, organization: product.organization, product:) }

      it "rejects a second snapshot for the same filter" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "without a product filter on the duplicate" do
      let(:product_filter) { create(:product_filter, organization: product.organization, product:) }
      let(:duplicate_product_filter) { nil }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with another product filter of the product" do
      let(:product_filter) { create(:product_filter, organization: product.organization, product:) }
      let(:duplicate_product_filter) { create(:product_filter, organization: product.organization, product:) }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with another contract of the organization" do
      let(:duplicate_contract) { create(:contract, organization: product.organization, customer: existing.contract.customer) }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with another product" do
      let(:duplicate_product) { create(:product, organization: product.organization) }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with another group" do
      let(:grouped_by) { {"region" => "eu"} }
      let(:duplicate_grouped_by) { {"region" => "us"} }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with a different period" do
      let(:duplicate_to_datetime) { existing.to_datetime + 1.month }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end
  end
end
