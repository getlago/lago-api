# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination do
  describe ".column_type" do
    it "returns the declared type of a key column" do
      expect(described_class.column_type(:issuing_date)).to eq(:date)
      expect(described_class.column_type(:created_at)).to eq(:time)
    end

    it "returns the declared type of a tiebreak" do
      expect(described_class.column_type(:id)).to eq(:uuid)
    end

    it "reads any other tiebreak as a string" do
      expect(described_class.column_type(:activity_id)).to eq(:string)
    end
  end
end
