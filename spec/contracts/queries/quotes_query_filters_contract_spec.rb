# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::QuotesQueryFiltersContract do
  subject(:result) { described_class.new.call(filters.to_h) }

  let(:filters) { {} }

  context "when filtering by customer" do
    let(:filters) { {customer: [SecureRandom.uuid]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by status" do
    let(:filters) { {status: "draft"} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when filter is an array" do
      let(:filters) { {status: ["draft", "approved"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filtering by number" do
    let(:filters) { {number: ["QT-2024-0001"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end

    context "when the number has more than 4 digits" do
      let(:filters) { {number: ["QT-2024-00001"]} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filtering by version" do
    let(:filters) { {version: [1, 2]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by from_date" do
    let(:filters) { {from_date: Date.today} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by to_date" do
    let(:filters) { {to_date: Date.today} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by owners" do
    let(:filters) { {owners: [SecureRandom.uuid]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filters are invalid" do
    it_behaves_like "an invalid filter", :customer, SecureRandom.uuid, ["must be an array"]
    it_behaves_like "an invalid filter", :customer, %w[random], {0 => ["is in invalid format"]}
    it_behaves_like "an invalid filter", :status, "random", ["must be one of: draft, approved, voided or must be an array"]
    it_behaves_like "an invalid filter", :status, ["draft", "random"], {1 => ["must be one of: draft, approved, voided"]}
    it_behaves_like "an invalid filter", :number, "QT-2024-0001", ["must be an array"]
    it_behaves_like "an invalid filter", :number, ["random"], {0 => ["is in invalid format"]}
    it_behaves_like "an invalid filter", :version, [0], {0 => ["must be greater than 0"]}
    it_behaves_like "an invalid filter", :version, [-1], {0 => ["must be greater than 0"]}
    it_behaves_like "an invalid filter", :version, ["not-an-integer"], {0 => ["must be an integer"]}
    it_behaves_like "an invalid filter", :from_date, "not-a-date", ["must be a date"]
    it_behaves_like "an invalid filter", :to_date, "not-a-date", ["must be a date"]
    it_behaves_like "an invalid filter", :owners, SecureRandom.uuid, ["must be an array"]
    it_behaves_like "an invalid filter", :owners, %w[random], {0 => ["is in invalid format"]}
  end
end
